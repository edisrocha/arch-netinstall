# 20-pacstrap.sh — instala o sistema base + manifesto no /mnt
banner "fase 20 — pacstrap"

if (( ! DRY_RUN )); then
  mountpoint -q /mnt || die "/mnt não está montado (rode a fase 10 antes)."
  mountpoint -q /mnt/boot || die "/mnt/boot (ESP) não está montado."
  # DNS dentro do chroot (o arch-chroot só faz bind se o arquivo existir)
  mkdir -p /mnt/etc
  cp -f /etc/resolv.conf /mnt/etc/resolv.conf 2>/dev/null || true
fi

mapfile -t PKGS < <(manifest_packages "$BASE_DIR")
case "$KERNEL" in
  both)   PKGS+=("linux" "linux-lts") ;;
  lts)    PKGS+=("linux-lts") ;;
  stable) PKGS+=("linux") ;;
esac

# base/base-devel/linux-firmware/intel-ucode já estão em packages/base.txt
info "instalando ${#PKGS[@]} pacotes (${KERNEL})"
run_sh "pacstrap -K /mnt ${PKGS[*]}"

# refresh do keyring dentro do novo sistema
run_sh "arch-chroot /mnt pacman -Sy --noconfirm --needed archlinux-keyring"

# --------------------------------------------------------------- fstab ------
info "gerando /etc/fstab"
if (( ! DRY_RUN )); then
  genfstab -U /mnt > /mnt/etc/fstab
  # swap explícita (systemd também autodetecta, mas fstab é determinístico)
  if ! grep -qE '^[^#].*[[:space:]]swap[[:space:]]' /mnt/etc/fstab; then
    printf '%s\tnone\tswap\tdefaults\t0 0\n' "UUID=$(uuid_of "$PART_SWAP")" >> /mnt/etc/fstab
  fi
  if [[ "$TMP_TMPFS" == "yes" ]]; then
    printf 'tmpfs\t/tmp\ttmpfs\tdefaults,noatime,mode=1777\t0 0\n' >> /mnt/etc/fstab
  fi
  ok "fstab:"
  sed 's/^/  /' /mnt/etc/fstab
fi

# ------------------------------------- leva o instalador para dentro do /mnt
run mkdir -p /mnt/root/netinstall
run rsync -a --delete --exclude logs/ --exclude '.git/' "$BASE_DIR/" /mnt/root/netinstall/
run cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
ok "instalador copiado para /mnt/root/netinstall"
