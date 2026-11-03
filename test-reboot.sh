#!/usr/bin/env bash
# test-reboot.sh — boota o disco da VM de teste sem ISO (valida o bootloader).
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"

TEST_DIR="$BASE_DIR/.test"
DISK_IMG="$TEST_DIR/arch-test.qcow2"
VARS="$TEST_DIR/OVMF_VARS.fd"
MEM="${TEST_MEM:-4096}"
CPUS="${TEST_CPUS:-2}"

[[ -f "$DISK_IMG" ]] || die "não existe $DISK_IMG — rode test-qemu.sh primeiro"
[[ -f "$VARS" ]] || die "não existe $VARS"

OVMF_CODE=""
for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
         /usr/share/edk2-ovmf/x64/OVMF_CODE.fd; do
  [[ -f "$c" ]] && { OVMF_CODE="$c"; break; }
done
[[ -n "$OVMF_CODE" ]] || die "OVMF_CODE não encontrado"

info "bootando o sistema instalado (sem ISO)..."
exec qemu-system-x86_64 \
  -enable-kvm -machine q35,accel=kvm -cpu host -smp "$CPUS" -m "$MEM" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK_IMG",if=virtio,format=qcow2,cache=writeback \
  -nic user,model=virtio-net-pci \
  -device virtio-vga -display gtk -boot order=c
