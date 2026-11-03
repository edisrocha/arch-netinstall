#!/usr/bin/env bash
# bootstrap.sh — baixa o arch-netinstall e executa o instalador.
#
# Do live ISO do Arch (você é root):
#   curl -fsSL https://raw.githubusercontent.com/edisrocha/arch-netinstall/main/bootstrap.sh \
#     | bash -s -- --disk /dev/sda
#
# Com dry-run (recomendado na primeira vez):
#   curl -fsSL .../bootstrap.sh | bash -s -- --disk /dev/sda --dry-run
#
# Variáveis:
#   NETINSTALL_REPO   (default edisrocha/arch-netinstall)
#   NETINSTALL_REF    (default main)  branch, tag ou commit
#   NETINSTALL_DIR    (default /root/netinstall)
#   NETINSTALL_NO_EXEC=1  só baixa e mostra o diretório (para testes)
set -Eeuo pipefail

REPO="${NETINSTALL_REPO:-edisrocha/arch-netinstall}"
REF="${NETINSTALL_REF:-main}"
DEST="${NETINSTALL_DIR:-/root/netinstall}"

say() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[bootstrap]\033[0m %s\n' "$*" >&2; exit 1; }

command -v tar >/dev/null || die "tar não encontrado"

# ------------------------------------------------------------- download ----
fetch() { # fetch URL DESTINO
  if command -v curl >/dev/null; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null; then
    wget -qO "$2" "$1"
  else
    die "nem curl nem wget disponíveis (pacman -Sy curl)"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL="https://codeload.github.com/$REPO/tar.gz/$REF"
if [[ -n "${NETINSTALL_TARBALL:-}" ]]; then
  say "usando tarball local: $NETINSTALL_TARBALL"
  cp -f "$NETINSTALL_TARBALL" "$TMP/src.tar.gz" || die "tarball local inválido"
else
  say "baixando $REPO@$REF"
  fetch "$URL" "$TMP/src.tar.gz" || die "falha no download de $URL"
fi

tar -xzf "$TMP/src.tar.gz" -C "$TMP" || die "tarball inválido"
SRC=$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)
[[ -n "$SRC" ]] || die "estrutura do tarball inesperada"

say "instalando em $DEST"
mkdir -p "$DEST"
if command -v rsync >/dev/null; then
  rsync -a --delete "$SRC/" "$DEST/"
else
  cp -a "$SRC/." "$DEST/"
fi

[[ -f "$DEST/install.sh" ]] || die "install.sh não encontrado após extrair"
chmod +x "$DEST"/*.sh 2>/dev/null || true
chmod +x "$DEST/phases"/*.sh 2>/dev/null || true

if [[ "${NETINSTALL_NO_EXEC:-0}" == "1" ]]; then
  say "NETINSTALL_NO_EXEC=1: conteúdo em $DEST"
  ls -1 "$DEST"
  exit 0
fi

say "executando install.sh $*"
exec bash "$DEST/install.sh" "$@"
