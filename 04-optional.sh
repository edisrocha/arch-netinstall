#!/usr/bin/env bash
# 04-optional.sh — extras que NÃO fazem parte do sistema base.
# Rode DEPOIS do primeiro boot, como usuário comum:
#   bash ~/Projetos/arch-netinstall/04-optional.sh
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
# shellcheck source=config.env
source "$BASE_DIR/config.env"

[[ ${EUID} -ne 0 ]] || die "rode como usuário comum (não root)."

banner "extras opcionais"

SKIP_NPM=0
SKIP_AUR=0
SKIP_OLLAMA=0
for a in "$@"; do
  case "$a" in
    --no-npm) SKIP_NPM=1 ;;
    --no-aur) SKIP_AUR=1 ;;
    --no-ollama) SKIP_OLLAMA=1 ;;
    *) die "opção desconhecida: $a" ;;
  esac
done

# ------------------------------------------------------------ npm globais ---
if (( ! SKIP_NPM )); then
  if confirm "instalar os pacotes npm globais (~900MB: 9router, claude, codex, esbuild, pixel-agents, traycer)?"; then
    info "npm -g"
    npm install -g 9router @anthropic-ai/claude-code @openai/codex \
                    @traycerai/cli esbuild pixel-agents 2>&1 | tail -5 || \
      warn "algum pacote npm falhou — veja a saída acima"
    # 9router só faz sentido depois que o npm -g existe
    UD="$HOME/.config/systemd/user"
    if [[ -f "$UD/9router.service" ]]; then
      mkdir -p "$UD/default.target.wants"
      ln -sfn ../9router.service "$UD/default.target.wants/9router.service"
      systemctl --user daemon-reload 2>/dev/null || true
      systemctl --user enable --now 9router.service 2>/dev/null || warn "habilite 9router manualmente"
      ok "9router habilitado"
    fi
  fi
fi

# ------------------------------------------------------------------- AUR ----
install_yay() {
  have_cmd yay && { ok "yay já instalado"; return 0; }
  info "compilando yay (AUR)"
  local tmp
  tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp/yay" || return 1
  ( cd "$tmp/yay" && makepkg -si --noconfirm ) || return 1
  rm -rf "$tmp"
}

if (( ! SKIP_AUR )); then
  if confirm "instalar pacotes AUR (yay, downgrade, qogir-icon-theme, arc-gtk-theme)?"; then
    if install_yay; then
      mapfile -t AUR < <(read_list "$BASE_DIR/packages/aur.txt")
      if (( ${#AUR[@]} )); then
        info "AUR: ${AUR[*]}"
        yay -S --needed --noconfirm "${AUR[@]}" || warn "algum pacote AUR falhou"
      fi
      ok "AUR concluído"
    else
      warn "falha ao compilar o yay"
    fi
  fi
fi

# ---------------------------------------------------------------- ollama ----
if (( ! SKIP_OLLAMA )); then
  if confirm "baixar um modelo do ollama agora (~2GB, llama3.2:3b)?"; then
    sudo systemctl enable --now ollama.service
    ollama pull llama3.2:3b || warn "pull falhou"
  fi
fi

banner "extras concluídos"
info "checklist manual:"
info "  - chaves SSH:    ssh-keygen -t ed25519   / restaurar de ~/.netinstall-backup-*"
info "  - GPG:           gpg --import <sua-chave>"
info "  - modelos ollama: ollama pull <modelo>"
info "  - dados do HD:   montar /dev/sdb1 e rsync do que precisar"
