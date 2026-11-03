#!/usr/bin/env bash
# sync-manifest.sh — reconcilia packages/*.txt com o sistema atual.
#
#   bash sync-manifest.sh          # só mostra o diff
#   bash sync-manifest.sh --write  # atualiza os arquivos
#
# - acrescenta pacotes instalados explicitamente que não estão em nenhum manifesto
# - remove do manifesto pacotes que não estão mais instalados
# - remove/ignora nomes EOS (não existem no Arch puro)
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"

WRITE=0
[[ "${1:-}" == "--write" ]] && WRITE=1

# pacotes EOS que o Arch puro não tem (intencionalmente fora do manifesto)
IGNORE=(arc-gtk-theme-eos downgrade dracut endeavouros-branding endeavouros-keyring
        endeavouros-mirrorlist endeavouros-xfce4-terminal-colors eos-apps-info eos-hooks
        eos-hwtool eos-lightdm-slick-theme eos-log-tool eos-packagelist eos-qogir-icons
        eos-quickstart eos-rankmirrors eos-settings-i3wm kernel-install-for-dracut
        reflector-simple welcome yay bash-app-translate linux linux-lts)

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

for f in base desktop dev extra; do
  [[ -f "$BASE_DIR/packages/$f.txt" ]] || : >"$BASE_DIR/packages/$f.txt"
  read_list "$BASE_DIR/packages/$f.txt" | sort -u >"$TMP/$f.txt"
done
cat "$TMP"/{base,desktop,dev,extra}.txt | sort -u >"$TMP/listed.txt"

pacman -Qqe | sort -u >"$TMP/installed.txt"
pacman -Qq  | sort -u >"$TMP/installed_all.txt"
printf '%s\n' "${IGNORE[@]}" | sort -u >"$TMP/ignore.txt"

# instalados explicitamente - listados - ignorados => novos
comm -23 "$TMP/installed.txt" <(sort -u "$TMP/listed.txt" "$TMP/ignore.txt") >"$TMP/new.txt"
# listados - instalados (qualquer) => obsoletos
comm -13 "$TMP/installed_all.txt" "$TMP/listed.txt" >"$TMP/stale.txt"

echo "novos (instalados, fora do manifesto):"
sed 's/^/  + /' "$TMP/new.txt" || true
echo "obsoletos (no manifesto, não instalados):"
sed 's/^/  - /' "$TMP/stale.txt" || true

(( WRITE )) || { echo; info "use --write para aplicar"; exit 0; }

# remove obsoletos de todos os arquivos
while read -r p; do
  [[ -z "$p" ]] && continue
  for f in base desktop dev extra; do
    [[ -s "$BASE_DIR/packages/$f.txt" ]] && \
      sed -i "/^${p}\$/d" "$BASE_DIR/packages/$f.txt"
  done
done <"$TMP/stale.txt"

# acrescenta novos em extra.txt
if [[ -s "$TMP/new.txt" ]]; then
  {
    echo
    echo "# adicionados por sync-manifest.sh em $(date -I)"
    cat "$TMP/new.txt"
  } >>"$BASE_DIR/packages/extra.txt"
fi

ok "manifests atualizados"
