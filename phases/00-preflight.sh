# 00-preflight.sh — nada é escrito no disco aqui.
# Valida ambiente, rede, espelhos e TODOS os nomes de pacote antes de destruir nada.
banner "fase 00 — preflight"

# ------------------------------------------------------------------ UEFI ----
[[ -d /sys/firmware/efi ]] || die "sistema não está em modo UEFI (necessário para systemd-boot)."
ok "UEFI detectado"

# --------------------------------------------------------------- ambiente ---
if [[ ! -d /run/archiso ]]; then
  warn "não parece ser o live ISO do Arch (/run/archiso ausente). Continuando mesmo assim."
fi
have_cmd pacstrap || die "pacstrap não encontrado — rode a partir do ISO do Arch."
have_cmd sgdisk  || die "sgdisk não encontrado (pacote gptfdisk)."
ok "ferramentas base presentes"

# ------------------------------------------------------------ relógio/TLS ---
run timedatectl set-ntp true
ok "NTP ativado"

# ------------------------------------------------------------------ rede ----
if ! ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
  err "sem conectividade com archlinux.org"
  cat <<'EOF'

  Se estiver no Wi-Fi:
    iwctl
      station list
      station wlan0 scan
      station wlan0 get-networks
      station wlan0 connect "SUA_REDE"
      quit
    # ou rode este instalador com: --wifi "SUA_REDE" "SENHA"

EOF
  die "resolva a rede e rode de novo."
fi
ok "rede OK"

# ------------------------------------------------------- keyring/espelhos ---
run pacman -Sy --noconfirm --needed archlinux-keyring
info "ranqueando espelhos ($MIRROR_COUNTRIES)"
run reflector --latest "$MIRROR_LATEST" --country "$MIRROR_COUNTRIES" --protocol https \
              --sort rate --save /etc/pacman.d/mirrorlist
run pacman -Syy --noconfirm
ok "espelhos atualizados"

# -------------------------------------------------- validação de pacotes ----
info "validando nomes de pacote do manifesto..."
mapfile -t PKGS < <(manifest_packages "$BASE_DIR")
(( ${#PKGS[@]} > 0 )) || die "manifesto de pacotes vazio"

case "$KERNEL" in
  both)   PKGS+=("linux" "linux-lts") ;;
  lts)    PKGS+=("linux-lts") ;;
  stable) PKGS+=("linux") ;;
  *)      die "KERNEL inválido: $KERNEL (use both|lts|stable)" ;;
esac

missing=()
for p in "${PKGS[@]}"; do
  pkg_exists "$p" || missing+=("$p")
done
if (( ${#missing[@]} )); then
  err "pacotes inexistentes nos repositórios oficiais:"
  printf '  - %s\n' "${missing[@]}"
  die "corrija packages/*.txt (nada foi escrito no disco)."
fi
ok "${#PKGS[@]} pacotes validados (kernel: $KERNEL)"

# ------------------------------------------------------------ disco alvo ----
size_gb=$(disk_size_gb "$DISK")
(( size_gb >= DISK_MIN_GB )) || die "disco $DISK tem ${size_gb}GB, mínimo ${DISK_MIN_GB}GB"
[[ "$DISK" != "/dev/"*"loop"* ]] || warn "disco loop detectado (teste?)"

# não permitir apagar o pendrive/ISO de onde estamos rodando
for dev in /dev/disk/by-label/Ventoy /run/archiso/bootmnt; do
  if [[ -e "$dev" ]]; then
    src_disk=$(lsblk -no PKNAME "$(readlink -f "$dev")" 2>/dev/null | head -1)
    if [[ -n "$src_disk" && "/dev/$src_disk" == "$DISK" ]]; then
      die "o disco $DISK contém a mídia de instalação. Escolha outro."
    fi
  fi
done

if disk_is_mounted "$DISK"; then
  err "há partições montadas em $DISK:"
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$DISK" || true
  die "desmonte antes de continuar."
fi

# resumo
echo
info "resumo da operação:"
cat <<EOF
  disco        : $DISK — $(disk_info "$DISK") (${size_gb}GB)
  partições    : ESP ${ESP_SIZE} (vfat) | swap ${SWAP_SIZE} | raiz ext4 (resto)
  bootloader   : $BOOTLOADER em /boot
  kernels      : $KERNEL
  usuário      : $USERNAME (grupos: $USER_GROUPS)
  dotfiles     : $INSTALL_DOTFILES
EOF
echo
if (( DRY_RUN )); then
  warn "modo dry-run: nenhuma escrita será feita no disco."
else
  confirm_typed "APAGAR" "TODOS os dados de $DISK serão destruídos. Continuar?" \
    || die "cancelado pelo usuário."
fi
ok "preflight concluído"
