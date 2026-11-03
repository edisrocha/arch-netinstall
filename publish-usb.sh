#!/usr/bin/env bash
# publish-usb.sh — copia o instalador para o pendrive Ventoy e gera o snapshot.
#
#   bash publish-usb.sh            # copia + snapshot + verificação
#   bash publish-usb.sh --check    # só verifica o que está no pendrive
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"

IO="${ARCH_ISO:-}"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

# ------------------------------------------------------- descobre o Ventoy --
USB_MNT=$(findmnt -n -o TARGET LABEL=Ventoy 2>/dev/null || true)
if [[ -z "$USB_MNT" ]]; then
  dev=$(readlink -f /dev/disk/by-label/Ventoy 2>/dev/null || true)
  [[ -n "$dev" ]] || die "pendrive Ventoy não encontrado (label Ventoy)"
  info "montando $dev"
  udisksctl mount -b "$dev" >/dev/null
  USB_MNT=$(findmnt -n -o TARGET LABEL=Ventoy)
fi
USB_DIR="$USB_MNT/netinstall"
info "pendrive: $USB_MNT"

# ISO: argumento/env, ou procura no pendrive e no diretório do repo
if [[ -z "$IO" ]]; then
  for c in "$USB_MNT"/archlinux-*.iso "$BASE_DIR"/archlinux-*.iso "$BASE_DIR"/../archlinux-*.iso; do
    [[ -f "$c" ]] && { IO="$c"; break; }
  done
fi

# -------------------------------------------------------------- ISO check ---
if [[ -f "$IO" ]]; then
  info "verificando sha256 do ISO ($(du -h "$IO" | cut -f1))"
  want=""
  if command -v curl >/dev/null; then
    ver=$(basename "$IO" | sed -n 's/^archlinux-\([0-9.]*\)-x86_64\.iso$/\1/p')
    if [[ -n "$ver" ]]; then
      want=$(curl -fsSL "https://archlinux.org/iso/$ver/sha256sums.txt" 2>/dev/null \
             | awk -v f="$(basename "$IO")" '$2==f {print $1; exit}' || true)
    fi
  fi
  got=$(sha256sum "$IO" | awk '{print $1}')
  if [[ -n "$want" ]]; then
    if [[ "$want" == "$got" ]]; then
      ok "sha256 do ISO confere ($got)"
    else
      err "sha256 NÃO confere!"
      err "  esperado: $want"
      err "  obtido  : $got"
    fi
  else
    warn "não consegui baixar o sha256sums.txt; valor local:"
    echo "  $got  $(basename "$IO")"
  fi
else
  warn "ISO não encontrado em $IO"
fi

(( CHECK_ONLY )) && { ls -la "$USB_DIR" 2>/dev/null || warn "netinstall/ ainda não publicado"; exit 0; }

# ------------------------------------------------------------- publicação ---
info "sincronizando $BASE_DIR -> $USB_DIR"
mkdir -p "$USB_DIR"
rsync -rt --no-perms --no-owner --no-group --delete \
      --exclude 'logs/' --exclude '.test/' --exclude '.git/' \
      "$BASE_DIR/" "$USB_DIR/"

STAMP=$(date +%Y%m%d)
SNAP="$USB_MNT/netinstall-$STAMP.tar.zst"
info "gerando snapshot $SNAP"
tar -C "$BASE_DIR" --exclude logs --exclude .test --exclude .git \
    -caf "$SNAP" .
( cd "$USB_MNT" && sha256sum "$(basename "$SNAP")" >"$(basename "$SNAP").sha256" )
ok "snapshot: $(du -h "$SNAP" | cut -f1)"

sync
info "conteúdo do pendrive:"
ls -lh "$USB_MNT" | sed 's/^/  /'
echo
ok "publique com segurança: udisksctl unmount -b $(readlink -f /dev/disk/by-label/Ventoy)"
