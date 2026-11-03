#!/usr/bin/env bash
# =============================================================================
# arch-netinstall — instalador one-shot de Arch Linux
#
# Uso (do live ISO oficial do Arch):
#   mount /dev/disk/by-label/Ventoy /mnt/usb
#   nvim /mnt/usb/netinstall/config.env
#   bash /mnt/usb/netinstall/install.sh --dry-run
#   bash /mnt/usb/netinstall/install.sh --disk /dev/sda
#
# Fases:
#   00 preflight  -> 10 disco -> 20 pacstrap -> 30 chroot (sistema, boot, usuário)
#   (dentro do chroot: 40 dotfiles/timers/repos -> 90 verificação)
# =============================================================================
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
# shellcheck source=config.env
source "$BASE_DIR/config.env"

PHASES=(00-preflight 10-disk 20-pacstrap 30-chroot)

usage() {
  cat <<EOF
arch-netinstall — instalação reprodutível de Arch Linux

  bash install.sh [opções]

Opções:
  --disk /dev/sdX        disco alvo (obrigatório; TODOS os dados serão apagados)
  --dry-run              mostra tudo sem tocar no disco
  --yes                  não pergunta confirmações (use só depois do --dry-run)
  --from N               começa na fase N (00, 10, 20, 30)
  --only N               roda somente a fase N
  --wifi SSID SENHA      conecta no Wi-Fi via iwctl antes de começar
  --no-dotfiles          não copia dotfiles/
  --config ARQUIVO       usa outro config.env
  -h, --help             esta ajuda

Exemplos:
  bash install.sh --dry-run
  bash install.sh --disk /dev/sda
  bash install.sh --disk /dev/vda --yes            # teste em QEMU
  bash install.sh --wifi "MinhaRede" "senha" --disk /dev/sda
EOF
}

FROM_PHASE=""
ONLY_PHASE=""
WIFI_SSID=""
WIFI_PASS=""

while (( $# )); do
  case "$1" in
    --disk)      DISK="${2:?--disk exige um dispositivo}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --yes|-y)    ASSUME_YES=1; shift ;;
    --from)      FROM_PHASE="${2:?--from exige um número de fase}"; shift 2 ;;
    --only)      ONLY_PHASE="${2:?--only exige um número de fase}"; shift 2 ;;
    --wifi)      WIFI_SSID="${2:?--wifi exige SSID}"; WIFI_PASS="${3:?--wifi exige senha}"; shift 3 ;;
    --no-dotfiles) INSTALL_DOTFILES="no"; shift ;;
    --config)    # shellcheck disable=SC1090
                 source "${2:?--config exige caminho}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "opção desconhecida: $1 (use --help)" ;;
  esac
done

export DRY_RUN ASSUME_YES BASE_DIR

# ---------------------------------------------------------------- log -------
mkdir -p "$BASE_DIR/logs" 2>/dev/null || true
if [[ -w "$BASE_DIR/logs" && "$LOG_TO_USB" == "yes" ]]; then
  LOG_FILE="$BASE_DIR/logs/install-$(date +%Y%m%d-%H%M%S).log"
else
  LOG_FILE="/tmp/netinstall-$(date +%Y%m%d-%H%M%S).log"
fi
: >"$LOG_FILE" 2>/dev/null || LOG_FILE=""
export LOG_FILE

# -------------------------------------------------------- wifi (opcional) ---
if [[ -n "$WIFI_SSID" ]]; then
  have_cmd iwctl || die "iwctl não encontrado"
  info "conectando no Wi-Fi '$WIFI_SSID'"
  iwctl --passphrase "$WIFI_PASS" station wlan0 connect "$WIFI_SSID" || die "falha ao conectar no Wi-Fi"
  for _ in {1..20}; do
    ping -c1 -W1 archlinux.org >/dev/null 2>&1 && break
    sleep 1
  done
fi

# ------------------------------------------------------------ validações ---
[[ -n "$DISK" ]] || { usage; die "faltou --disk /dev/sdX"; }
disk_exists "$DISK" || die "disco inexistente: $DISK"
need_root

export DISK USERNAME USER_SHELL HOSTNAME USER_GROUPS TIMEZONE LOCALE KEYMAP \
       X11_LAYOUT X11_MODEL ESP_SIZE SWAP_SIZE LABEL_ESP LABEL_ROOT LABEL_SWAP \
       DISK_MIN_GB KERNEL BOOTLOADER BOOT_TIMEOUT BOOT_DEFAULT \
       MIRROR_COUNTRIES MIRROR_LATEST DESKTOP DISPLAY_MANAGER SESSION AUTOLOGIN \
       DESKTOP_APPS INSTALL_DOTFILES REPOS INSTALL_AUR GIT_NAME GIT_EMAIL \
       TMP_TMPFS ZRAM PACSTRAP_RETRIES

# Seleção de fases
selected=()
if [[ -n "$ONLY_PHASE" ]]; then
  case "$ONLY_PHASE" in
    0|00) selected=(00-preflight) ;;
    1|10) selected=(10-disk) ;;
    2|20) selected=(20-pacstrap) ;;
    3|30) selected=(30-chroot) ;;
    *) die "fase inválida para --only: $ONLY_PHASE" ;;
  esac
elif [[ -n "$FROM_PHASE" ]]; then
  case "$FROM_PHASE" in
    0|00) selected=("${PHASES[@]}") ;;
    1|10) selected=(10-disk 20-pacstrap 30-chroot) ;;
    2|20) selected=(20-pacstrap 30-chroot) ;;
    3|30) selected=(30-chroot) ;;
    *) die "fase inválida para --from: $FROM_PHASE" ;;
  esac
else
  selected=("${PHASES[@]}")
fi

banner "arch-netinstall — Arch Linux $([[ $DRY_RUN == 1 ]] && echo '(DRY-RUN)')"
info "config      : $BASE_DIR/config.env"
info "disco alvo  : $DISK — $(disk_info "$DISK")"
info "hostname    : $HOSTNAME   usuário: $USERNAME"
info "kernel      : $KERNEL     boot: $BOOTLOADER"
info "desktop     : $DESKTOP ($SESSION, autologin=$AUTOLOGIN)"
info "locale      : $LOCALE / $KEYMAP / $TIMEZONE"
info "fases       : ${selected[*]}"
info "log         : ${LOG_FILE:-<sem log>}"
echo

# ------------------------------------------------------------- executor ----
FAILED_PHASE=""
on_error() {
  local rc=$? line=$1
  err "falhou (rc=$rc) na linha $line"
  [[ -n "$FAILED_PHASE" ]] && err "fase: $FAILED_PHASE"
  err "log completo: ${LOG_FILE:-<sem log>}"
  exit "$rc"
}
trap 'on_error $LINENO' ERR

START_TS=$(date +%s)
for phase in "${selected[@]}"; do
  FAILED_PHASE="$phase"
  script="$BASE_DIR/phases/$phase.sh"
  [[ -f "$script" ]] || die "fase não encontrada: $script"
  # shellcheck disable=SC1090
  source "$script"
done
FAILED_PHASE=""
trap - ERR

END_TS=$(date +%s)
banner "concluído em $(( (END_TS - START_TS) / 60 ))m $(( (END_TS - START_TS) % 60 ))s"
ok "sistema instalado em $DISK"
info "próximos passos:"
info "  1. reboot (remova a ISO/pendrive do boot)"
info "  2. login como $USERNAME"
info "  3. bash ~/Projetos/arch-netinstall/04-optional.sh   # npm globals, AUR extra"
info "log: ${LOG_FILE:-<sem log>}"
