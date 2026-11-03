# chroot-system.sh — roda DENTRO do /mnt (via arch-chroot), como root.
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/common.sh
source "$BASE_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/config.env"
# shellcheck source=/dev/null
[[ -f "$BASE_DIR/run.env" ]] && source "$BASE_DIR/run.env"

trap 'err "falhou na linha $LINENO: $BASH_COMMAND"; exit 1' ERR

# ------------------------------------------------------------- relógio ------
info "timezone: $TIMEZONE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# -------------------------------------------------------------- locale ------
info "locale: $LOCALE"
sed -i "s/^#\\(${LOCALE} UTF-8\\)/\\1/" /etc/locale.gen
grep -q "^${LOCALE} UTF-8" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
cat >/etc/locale.conf <<EOF
LANG=$LOCALE
LC_ADDRESS=$LOCALE
LC_IDENTIFICATION=$LOCALE
LC_MEASUREMENT=$LOCALE
LC_MONETARY=$LOCALE
LC_NAME=$LOCALE
LC_NUMERIC=$LOCALE
LC_PAPER=$LOCALE
LC_TELEPHONE=$LOCALE
LC_TIME=$LOCALE
EOF

# --------------------------------------------------------------- teclado ----
cat >/etc/vconsole.conf <<EOF
KEYMAP=$KEYMAP
EOF
mkdir -p /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$X11_LAYOUT"
        Option "XkbModel"  "$X11_MODEL"
EndSection
EOF

# ------------------------------------------------------------- hostname -----
echo "$HOSTNAME" >/etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# ------------------------------------------------------------ usuário -------
if ! id "$USERNAME" &>/dev/null; then
  info "criando usuário $USERNAME"
  useradd -m -G "$USER_GROUPS" -s "$USER_SHELL" "$USERNAME"
else
  info "usuário $USERNAME já existe"
  for g in ${USER_GROUPS//,/ }; do
    getent group "$g" >/dev/null && usermod -aG "$g" "$USERNAME"
  done
fi

if [[ -n "${USER_PASSWORD:-}" ]]; then
  echo "$USERNAME:$USER_PASSWORD" | chpasswd
  ok "senha definida via USER_PASSWORD"
else
  echo
  info "defina a senha do usuário $USERNAME:"
  passwd "$USERNAME" || die "falha ao definir senha"
fi

mkdir -p /etc/sudoers.d
cat >/etc/sudoers.d/10-"$USERNAME" <<EOF
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 440 /etc/sudoers.d/10-"$USERNAME"
visudo -c -f /etc/sudoers.d/10-"$USERNAME" >/dev/null || die "sudoers inválido"
ok "sudo liberado para o grupo wheel"

# ------------------------------------------------------------- serviços -----
# unidade custom (governor de CPU) — precisa existir ANTES do enable
if [[ -f "$BASE_DIR/units/cpu-governor.service" ]]; then
  install -Dm644 "$BASE_DIR/units/cpu-governor.service" /etc/systemd/system/cpu-governor.service
fi

info "habilitando serviços de sistema"
while read -r unit; do
  [[ -z "$unit" ]] && continue
  systemctl enable "$unit" >/dev/null 2>&1 && ok "  $unit" || warn "  falhou: $unit"
done < <(read_list "$BASE_DIR/services/system.list")

# zram
if [[ "$ZRAM" == "yes" ]]; then
  cat >/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF
fi

# ------------------------------------------------------------- lightdm ------
if [[ "$DISPLAY_MANAGER" == "lightdm" ]]; then
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat >/etc/lightdm/lightdm.conf.d/50-netinstall.conf <<EOF
[LightDM]
logind-check-graphical=true

[Seat:*]
greeter-session=lightdm-slick-greeter
allow-user-switching=true
user-session=$SESSION
$([[ "$AUTOLOGIN" == "yes" ]] && echo "autologin-user=$USERNAME")
EOF
fi

# --------------------------------------------------------------- initramfs --
info "mkinitcpio: módulo i915 + microcode"
if ! grep -q '^MODULES=.*i915' /etc/mkinitcpio.conf; then
  sed -i 's/^MODULES=(\(.*\))/MODULES=(i915 \1)/' /etc/mkinitcpio.conf
  sed -i 's/^MODULES=()/MODULES=(i915)/' /etc/mkinitcpio.conf
fi
if ! grep -q 'microcode' /etc/mkinitcpio.conf; then
  sed -i 's/^HOOKS=(base udev /HOOKS=(base udev microcode /' /etc/mkinitcpio.conf
fi
grep -E '^MODULES=|^HOOKS=' /etc/mkinitcpio.conf

mkinitcpio -P

# ------------------------------------------------------------------ boot ----
info "bootloader: $BOOTLOADER"
if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
  if [[ -d /sys/firmware/efi/efivars ]]; then
    bootctl install --esp-path=/boot || bootctl install --esp-path=/boot --no-variables
  else
    bootctl install --esp-path=/boot --no-variables
  fi

  cat >/boot/loader/loader.conf <<EOF
default $BOOT_DEFAULT
timeout $BOOT_TIMEOUT
console-mode max
editor  no
EOF

  mkdir -p /boot/loader/entries
  for k in linux linux-lts; do
    [[ -f "/boot/vmlinuz-$k" ]] || continue
    name="$k"; [[ "$k" == "linux" ]] && name="stable"
    cat >"/boot/loader/entries/arch-$name.conf" <<EOF
title   Arch Linux ($k)
linux   /vmlinuz-$k
initrd  /intel-ucode.img
initrd  /initramfs-$k.img
options root=UUID=$ROOT_UUID rw quiet loglevel=3
EOF
    ok "entry: arch-$name.conf"
  done

  # default: usa o que existir de fato
  if [[ ! -f "/boot/loader/entries/$BOOT_DEFAULT" ]]; then
    fallback=$(basename -a /boot/loader/entries/*.conf 2>/dev/null | head -1)
    warn "default $BOOT_DEFAULT não existe; usando ${fallback:-<nenhum>}"
    [[ -n "$fallback" ]] && sed -i "s/^default .*/default $fallback/" /boot/loader/loader.conf
  fi
  bootctl --esp-path=/boot list >/dev/null 2>&1 && ok "bootctl OK"
else
  die "BOOTLOADER não suportado: $BOOTLOADER"
fi

# ------------------------------------------------- extras do sistema -------
# fstrim/paccache já vêm dos timers habilitados em services/system.list
mkdir -p /etc/pacman.d/hooks
cat >/etc/pacman.d/hooks/00-netinstall-reflector.hook <<'EOF'
[Trigger]
Operation = Upgrade
Type = Package
Target = pacman-mirrorlist

[Action]
Description = Atualizando espelhos (reflector)...
When = PostTransaction
Exec = /usr/bin/reflector --latest 20 --country Brazil,Chile,Argentina,United States --protocol https --sort rate --save /etc/pacman.d/mirrorlist
EOF

ok "sistema base configurado"

# ------------------------------------------------- pós-instalação (user) ----
if [[ "$INSTALL_DOTFILES" == "yes" ]]; then
  info "rodando fase 40 como $USERNAME"
  runuser -u "$USERNAME" -- env HOME="/home/$USERNAME" \
    bash "$BASE_DIR/phases/40-post.sh" || warn "fase 40 retornou erro (veja o log)"
fi

# ------------------------------------------------------------ verificação ---
bash "$BASE_DIR/phases/90-verify.sh" || warn "verificação encontrou pendências"
