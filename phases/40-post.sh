# 40-post.sh — roda como USUÁRIO comum (via runuser): dotfiles, timers, repos.
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/common.sh
source "$BASE_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/config.env"
# shellcheck source=/dev/null
[[ -f "$BASE_DIR/run.env" ]] && source "$BASE_DIR/run.env"

banner "fase 40 — pós-instalação do usuário ($USERNAME)"

[[ "$(id -un)" == "$USERNAME" ]] || die "esta fase deve rodar como $USERNAME (atual: $(id -un))"

# ------------------------------------------------------------- dotfiles -----
if [[ -d "$BASE_DIR/dotfiles" ]]; then
  info "copiando dotfiles (backup do que existir em ~/.netinstall-backup)"
  BK="$HOME/.netinstall-backup-$(date +%Y%m%d-%H%M%S)"
  run rsync -rlptD --no-owner --no-group --backup --backup-dir="$BK" \
            "$BASE_DIR/dotfiles/" "$HOME/"
  ok "dotfiles aplicados"
fi

# -------------------------------------------------- instalador no home -----
if [[ -d /root/netinstall && ! -d "$HOME/Projetos/arch-netinstall" ]]; then
  info "copiando instalador para ~/Projetos/arch-netinstall"
  mkdir -p "$HOME/Projetos"
  rsync -rlptD --no-owner --no-group --exclude 'logs/' --exclude '.test/' \
        --exclude '.git/' /root/netinstall/ "$HOME/Projetos/arch-netinstall/" \
        || warn "cópia do instalador falhou"
fi

# ------------------------------------------------------- estrutura do home --
mkdir -p "$HOME/Projetos" "$HOME/Documentos" "$HOME/Imagens" "$HOME/Downloads"
have_cmd xdg-user-dirs-update && (xdg-user-dirs-update || true)

# --------------------------------------------------------- unidades user ----
info "instalando unidades systemd --user"
UD="$HOME/.config/systemd/user"
mkdir -p "$UD/default.target.wants" "$UD/timers.target.wants"
shopt -s nullglob
for u in "$BASE_DIR"/units/user/*; do
  install -Dm644 "$u" "$UD/$(basename "$u")"
done
shopt -u nullglob

# timers habilitados já na instalação (o 9router só depois do npm -g)
for t in nexmatch-backup.timer limpar-caches.timer; do
  [[ -f "$UD/$t" ]] || continue
  ln -sfn "../$t" "$UD/timers.target.wants/$t"
  ok "  timer: $t"
done

# -------------------------------------------------------------- git config --
if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  git config --global user.name  "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  ok "git identity: $GIT_NAME <$GIT_EMAIL>"
fi

# ----------------------------------------------------------------- repos ----
if [[ -n "$REPOS" ]]; then
  info "clonando repositórios"
  for repo in $REPOS; do
    name="$(basename "$repo" .git)"
    dest="$HOME/Projetos/$name"
    if [[ -d "$dest/.git" ]]; then
      ok "  $name já existe"
      continue
    fi
    if git clone "$repo" "$dest" 2>/dev/null; then
      ok "  $name"
    else
      warn "  falhou: $repo (chave SSH/rede? clone depois manualmente)"
    fi
  done
fi

ok "fase 40 concluída"
echo
info "instalador copiado para ~/Projetos/arch-netinstall"
info "pós-boot (como $USERNAME):"
info "  bash ~/Projetos/arch-netinstall/04-optional.sh"
