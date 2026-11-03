# 30-chroot.sh — configura o sistema dentro do /mnt via arch-chroot
banner "fase 30 — chroot (sistema, usuário, boot)"

(( DRY_RUN )) || mountpoint -q /mnt || die "/mnt não está montado."

# arch-chroot monta /proc /sys /dev, o efivarfs e copia o resolv.conf sozinho.
cp -f /etc/resolv.conf /mnt/etc/resolv.conf 2>/dev/null || true

# ambiente exportado para dentro do chroot
ENVFILE=/mnt/root/netinstall/run.env
if (( ! DRY_RUN )); then
  {
    echo "# gerado por 30-chroot.sh em $(date -Is)"
    for v in USERNAME USER_SHELL HOSTNAME USER_GROUPS TIMEZONE LOCALE KEYMAP \
             X11_LAYOUT X11_MODEL KERNEL BOOTLOADER BOOT_TIMEOUT BOOT_DEFAULT \
             DISPLAY_MANAGER SESSION AUTOLOGIN DESKTOP_APPS INSTALL_DOTFILES \
             REPOS INSTALL_AUR GIT_NAME GIT_EMAIL TMP_TMPFS ZRAM LOG_TO_USB \
             DRY_RUN ASSUME_YES ROOT_UUID PART_SWAP; do
      printf 'export %s=%q\n' "$v" "${!v:-}"
    done
    [[ -n "${USER_PASSWORD:-}" ]] && printf 'export USER_PASSWORD=%q\n' "$USER_PASSWORD"
  } >"$ENVFILE"
  chmod 600 "$ENVFILE"
fi

run arch-chroot /mnt /bin/bash -c \
  'cd /root/netinstall && bash phases/chroot-system.sh'

# -------------------------------------------------- entrada UEFI (NVRAM) ----
# Dentro do chroot o efivarfs não está disponível; criamos a entrada pelo host.
if (( ! DRY_RUN )) && have_cmd efibootmgr; then
  loader='\EFI\systemd\systemd-bootx64.efi'
  if efibootmgr -v 2>/dev/null | grep -qiF 'systemd-bootx64.efi'; then
    ok "entrada UEFI para systemd-boot já existe"
  else
    info "criando entrada UEFI no firmware"
    efibootmgr --create --disk "$DISK" --part 1 \
      --label "Linux Boot Manager" --loader "$loader" >/dev/null \
      && ok "entrada UEFI criada" \
      || warn "não consegui criar a entrada UEFI (o firmware pode já apontar para o mesmo caminho)"
  fi
fi

ok "fase 30 concluída"
