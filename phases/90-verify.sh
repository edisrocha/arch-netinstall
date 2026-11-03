# 90-verify.sh — confere o resultado. Não altera nada.
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/common.sh
source "$BASE_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/config.env"
# shellcheck source=/dev/null
[[ -f "$BASE_DIR/run.env" ]] && source "$BASE_DIR/run.env"

banner "fase 90 — verificação"
ISSUES=0
problem() { warn "$*"; ISSUES=$((ISSUES + 1)); }

# ------------------------------------------------------------- pacotes ------
expected=()
while IFS= read -r p; do expected+=("$p"); done < <(
  { manifest_packages "$BASE_DIR"; printf '%s\n' linux linux-lts; } | sort -u
)
installed=$(pacman -Qq | sort -u)
missing=()
for p in "${expected[@]}"; do
  grep -qx "$p" <<<"$installed" || missing+=("$p")
done
if (( ${#missing[@]} )); then
  problem "pacotes do manifesto ausentes (${#missing[@]}): ${missing[*]}"
else
  ok "todos os ${#expected[@]} pacotes do manifesto estão instalados"
fi

# ------------------------------------------------------------ serviços ------
while IFS= read -r unit; do
  [[ -z "$unit" ]] && continue
  if systemctl is-enabled "$unit" &>/dev/null; then
    ok "habilitado: $unit"
  elif [[ -e "/etc/systemd/system/$unit" || -e "/usr/lib/systemd/system/$unit" ]]; then
    problem "não habilitado: $unit"
  else
    problem "unidade inexistente: $unit"
  fi
done < <(read_list "$BASE_DIR/services/system.list")

# ------------------------------------------------------------- usuário ------
for g in ${USER_GROUPS//,/ }; do
  id -nG "$USERNAME" | tr ' ' '\n' | grep -qx "$g" || problem "usuário fora do grupo: $g"
done
ok "grupos de $USERNAME: $(id -nG "$USERNAME")"

# ---------------------------------------------------------------- boot ------
if [[ -f /boot/loader/loader.conf ]]; then
  ok "loader.conf presente"
  ls /boot/loader/entries/*.conf >/dev/null 2>&1 && ok "entries: $(basename -a /boot/loader/entries/*.conf | tr '\n' ' ')" \
    || problem "nenhum entry em /boot/loader/entries"
  for f in /boot/vmlinuz-linux*; do
    [[ -f "$f" ]] && ok "kernel: $f"
  done
  [[ -f /boot/EFI/systemd/systemd-bootx64.efi ]] && ok "systemd-boot instalado na ESP" \
    || problem "systemd-boot ausente na ESP"
else
  problem "loader.conf ausente (bootloader não configurado)"
fi

# --------------------------------------------------------------- locale -----
grep -q "$LOCALE" /etc/locale.conf 2>/dev/null && ok "locale: $LOCALE" || problem "locale não configurado"
[[ -L /etc/localtime ]] && ok "timezone: $(readlink /etc/localtime | sed 's|.*/zoneinfo/||')" || problem "timezone não configurado"

# ---------------------------------------------------------------- resumo ----
echo
if (( ISSUES == 0 )); then
  ok "verificação limpa — nenhuma pendência"
else
  warn "$ISSUES pendência(s) encontradas acima"
fi
exit 0
