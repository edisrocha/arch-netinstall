#!/usr/bin/env bash
# test-qemu.sh — testa a instalação numa VM UEFI, sem encostar no hardware real.
#
#   bash test-qemu.sh            # cria/reaproveita a VM e boota o ISO do Arch
#   bash test-qemu.sh --reset    # apaga o disco de teste e começa do zero
#
# Requisitos (o script oferece instalar): qemu-desktop, edk2-ovmf, libisoburn
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"

TEST_DIR="$BASE_DIR/.test"
mkdir -p "$TEST_DIR"
DISK_IMG="$TEST_DIR/arch-test.qcow2"
VARS="$TEST_DIR/OVMF_VARS.fd"
NETISO="$TEST_DIR/netinstall.iso"
DISK_GB="${TEST_DISK_GB:-40}"
MEM="${TEST_MEM:-4096}"
CPUS="${TEST_CPUS:-2}"
ARCH_ISO="${ARCH_ISO:-}"
RESET=0
[[ "${1:-}" == "--reset" ]] && RESET=1

# --------------------------------------------------------------- deps -------
need_pkgs=()
have_cmd qemu-system-x86_64 || need_pkgs+=(qemu-desktop)
have_cmd xorriso || need_pkgs+=(libisoburn)
[[ -f /usr/share/edk2/x64/OVMF_CODE.4m.fd || -f /usr/share/edk2-ovmf/x64/OVMF_CODE.fd ]] || need_pkgs+=(edk2-ovmf)

if (( ${#need_pkgs[@]} )); then
  warn "faltam: ${need_pkgs[*]}"
  confirm "instalar agora com pacman?" || die "instale manualmente: sudo pacman -S ${need_pkgs[*]}"
  sudo pacman -S --needed --noconfirm "${need_pkgs[@]}"
fi

# ISO do Arch: argumento, env, ou procura perto do repo / no Ventoy
if [[ -z "$ARCH_ISO" ]]; then
  for c in "$BASE_DIR"/archlinux-*.iso "$BASE_DIR"/../archlinux-*.iso \
           /run/media/*/Ventoy/archlinux-*.iso /run/media/*/*/archlinux-*.iso; do
    [[ -f "$c" ]] && { ARCH_ISO="$c"; break; }
  done
fi
[[ -n "$ARCH_ISO" && -f "$ARCH_ISO" ]] || die "ISO do Arch não encontrado (use ARCH_ISO=/caminho/archlinux.iso)"

# ---------------------------------------------------------------- OVMF ------
OVMF_CODE=""
for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
         /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd; do
  [[ -f "$c" ]] && { OVMF_CODE="$c"; break; }
done
[[ -n "$OVMF_CODE" ]] || die "OVMF_CODE não encontrado"
OVMF_VARS_SRC="${OVMF_CODE/CODE/VARS}"

# ------------------------------------------------------------ netinstall ----
info "gerando $NETISO"
rm -f "$NETISO"
xorriso -as mkisofs -R -J -joliet-long -V NETINSTALL \
  -m logs -m .test -m .git \
  -o "$NETISO" "$BASE_DIR" >/dev/null 2>&1 || die "falha no xorriso"
ok "netinstall.iso ($(du -h "$NETISO" | cut -f1))"

# ---------------------------------------------------------------- disco -----
if (( RESET )) && [[ -f "$DISK_IMG" ]]; then
  warn "apagando disco de teste anterior"
  rm -f "$DISK_IMG"
fi
if [[ ! -f "$DISK_IMG" ]]; then
  info "criando disco de teste de ${DISK_GB}G (qcow2 esparso)"
  qemu-img create -f qcow2 "$DISK_IMG" "${DISK_GB}G" >/dev/null
fi
[[ -f "$VARS" ]] || cp "$OVMF_VARS_SRC" "$VARS"

cat <<EOF

  VM pronta. Dentro do live ISO, rode:

    lsblk                                  # confirme que o disco é /dev/vda
    mount /dev/sr1 /mnt/usb                # netinstall.iso (segundo CD-ROM)
    bash /mnt/usb/install.sh --dry-run
    bash /mnt/usb/install.sh --disk /dev/vda

  Depois de instalar, feche a VM e rode:  bash test-reboot.sh

EOF
read -r -p "Enter para iniciar a VM..."

exec qemu-system-x86_64 \
  -enable-kvm -machine q35,accel=kvm -cpu host -smp "$CPUS" -m "$MEM" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK_IMG",if=virtio,format=qcow2,cache=writeback \
  -cdrom "$ARCH_ISO" \
  -drive file="$NETISO",media=cdrom,readonly=on \
  -nic user,model=virtio-net-pci \
  -device virtio-vga -display gtk -boot order=d
