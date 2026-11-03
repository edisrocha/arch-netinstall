#!/usr/bin/env bash
# Limpeza periodica de caches regeneraveis do usuario (para aliviar o SSD).
# Nao toca em modelos baixados (huggingface, ms-playwright) para evitar re-download.
set -u

LOG="$HOME/.local/state/limpar-caches.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

usado_antes=$(df --output=used / | tail -1 | tr -d ' ')
log "inicio (usado ${usado_antes}K)"

for d in pip go-build mozilla chromium chromium-headless mesa_shader_cache node-systray yay; do
  p="$HOME/.cache/$d"
  [ -d "$p" ] || continue
  sz=$(du -sh "$p" 2>/dev/null | cut -f1)
  rm -rf "$p" && log "removido ~/.cache/$d ($sz)"
done

if command -v npm >/dev/null 2>&1; then
  npm cache clean --force >/dev/null 2>&1 && log "npm cache limpo"
fi

usado_depois=$(df --output=used / | tail -1 | tr -d ' ')
log "fim (usado ${usado_depois}K, liberado $(( (usado_antes - usado_depois) / 1024 )) MB)"
