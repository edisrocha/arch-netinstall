#!/usr/bin/env bash
# lib/common.sh — funções compartilhadas.
# Compatível com bash 4+ (ISO do Arch, chroot e máquina instalada).
[[ -n "${__COMMON_SH:-}" ]] && return 0
__COMMON_SH=1

if [[ -t 1 ]]; then
  C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
  C_BLU=$'\033[1;34m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_DIM=''; C_RST=''
fi

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
LOG_FILE="${LOG_FILE:-}"

# _emit MENSAGEM [fd]
_emit() {
  local msg="$1" fd="${2:-1}"
  printf '%s\n' "$msg" >&"$fd"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s %s\n' "$(date '+%F %T')" "$msg" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

info() { _emit "${C_BLU}[info]${C_RST} $*"; }
ok()   { _emit "${C_GRN}[ ok ]${C_RST} $*"; }
warn() { _emit "${C_YEL}[warn]${C_RST} $*" 2; }
err()  { _emit "${C_RED}[erro]${C_RST} $*" 2; }
dbg()  { [[ "${DEBUG:-0}" == 1 ]] && _emit "${C_DIM}[dbg ]${C_RST} $*"; return 0; }

die() { err "$*"; exit 1; }

banner() {
  _emit ""
  _emit "${C_BLU}==================================================================${C_RST}"
  _emit "${C_BLU} $*${C_RST}"
  _emit "${C_BLU}==================================================================${C_RST}"
}

# run CMD... — executa, ou apenas imprime em --dry-run
run() {
  if (( DRY_RUN )); then
    printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$*"
    _emit "dry-run: $*"
    return 0
  fi
  "$@"
}

# run_sh "comando com pipes" — mesma coisa, via bash -c
run_sh() {
  if (( DRY_RUN )); then
    printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$1"
    _emit "dry-run: $1"
    return 0
  fi
  bash -c "$1"
}

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "rode como root (no live da ISO você já é root)."
}

# confirm "pergunta" — aceita s/sim/y/yes
confirm() {
  if (( ASSUME_YES )); then
    ok "auto-confirmado (--yes): $1"
    return 0
  fi
  local ans
  printf '%s%s%s [s/N] ' "$C_YEL" "$1" "$C_RST"
  read -r ans || return 1
  [[ $ans =~ ^([sS]|[sS][iI][mM]|[yY]|[yY][eE][sS])$ ]]
}

# confirm_typed "texto esperado" "pergunta"
confirm_typed() {
  local expected="$1" question="$2" ans
  if (( ASSUME_YES )); then
    ok "auto-confirmado (--yes): $question"
    return 0
  fi
  printf '%s%s%s\n  digite exatamente %s%s%s para confirmar: ' \
    "$C_YEL" "$question" "$C_RST" "$C_RED" "$expected" "$C_RST"
  read -r ans || return 1
  [[ "$ans" == "$expected" ]]
}

# part_suffix /dev/nvme0n1 -> p   |   /dev/sda -> (vazio)
part_suffix() {
  local d="${1##*/}"
  if [[ $d =~ (nvme|mmcblk|loop|md|dm-) ]]; then printf 'p'; else printf ''; fi
}

disk_exists() { [[ -b "$1" ]]; }

# disk_info /dev/sda -> "MODEL | SIZE | SERIAL"
disk_info() {
  lsblk -dn -o MODEL,SIZE,SERIAL "$1" 2>/dev/null | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

disk_size_gb() {
  local bytes
  # lsblk funciona sem root (blockdev --getsize64 exige privilégio)
  bytes=$(lsblk -bdno SIZE "$1" 2>/dev/null | head -1) || { echo 0; return; }
  [[ -n "$bytes" ]] || { echo 0; return; }
  echo $(( bytes / 1024 / 1024 / 1024 ))
}

# qualquer partição do disco montada?
disk_is_mounted() {
  local disk="$1" mp
  while read -r mp; do
    [[ -n "$mp" ]] && return 0
  done < <(lsblk -nlo MOUNTPOINT "$disk" 2>/dev/null)
  return 1
}

# retry N cmd...
retry() {
  local n=$1; shift
  local i
  for (( i = 1; i <= n; i++ )); do
    "$@" && return 0
    warn "tentativa $i/$n falhou: $*"
    (( i < n )) && sleep 3
  done
  return 1
}

# Índice de nomes de pacotes dos repositórios (uma leitura só: pacman -Si é lento)
pkg_index_file() {
  if [[ -z "${_PKG_INDEX_CACHE:-}" ]]; then
    _PKG_INDEX_CACHE="${TMPDIR:-/tmp}/netinstall-pkgindex.$$"
    pacman -Slq 2>/dev/null | sort -u >"$_PKG_INDEX_CACHE"
    export _PKG_INDEX_CACHE
  fi
  printf '%s' "$_PKG_INDEX_CACHE"
}

pkg_exists() { grep -qxF -- "$1" "$(pkg_index_file)"; }

# read_list arquivo — uma entrada por linha, ignora # e vazias
read_list() {
  [[ -f "$1" ]] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' "$1" \
    | grep -v '^$' || true
}

# backup_path caminho -> caminho.bak.<epoch>
backup_path() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  local b="${p}.bak.$(date +%s)"
  run mv "$p" "$b"
  dbg "backup: $p -> $b"
}

# install_file origem destino [modo]
install_file() {
  local src="$1" dst="$2" mode="${3:-}"
  run install -Dm"${mode:-644}" "$src" "$dst"
}

# symlink_force alvo link
symlink_force() {
  run ln -sfn "$1" "$2"
}

# arch_chroot_disponivel?
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# uuid_of /dev/sda3
uuid_of() { blkid -s UUID -o value "$1"; }

# Lista de pacotes do manifesto (base + desktop + dev + extra)
manifest_packages() {
  local root="$1"
  {
    read_list "$root/packages/base.txt"
    read_list "$root/packages/desktop.txt"
    read_list "$root/packages/dev.txt"
    read_list "$root/packages/extra.txt"
  } | sort -u
}

# junta pacotes em uma linha
join_pkgs() { tr '\n' ' ' | sed 's/ *$//'; }
