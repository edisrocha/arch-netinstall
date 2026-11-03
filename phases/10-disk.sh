# 10-disk.sh — particiona e formata o disco alvo. DESTRUTIVO.
banner "fase 10 — disco ($DISK)"

SUF=$(part_suffix "$DISK")
PART_ESP="${DISK}${SUF}1"
PART_SWAP="${DISK}${SUF}2"
PART_ROOT="${DISK}${SUF}3"

info "layout: $PART_ESP (ESP $ESP_SIZE) | $PART_SWAP (swap $SWAP_SIZE) | $PART_ROOT (ext4, resto)"

# ------------------------------------------------------------- limpeza ------
info "zerando tabela de partições"
run sgdisk --zap-all "$DISK"
run wipefs -a "$DISK"

# ------------------------------------------------------------ partições -----
run sgdisk \
  -n "1:0:+${ESP_SIZE}"  -t 1:ef00 -c "1:${LABEL_ESP}" \
  -n "2:0:+${SWAP_SIZE}" -t 2:8200 -c "2:${LABEL_SWAP}" \
  -n "3:0:0"             -t 3:8300 -c "3:${LABEL_ROOT}" \
  "$DISK"

run partprobe "$DISK" 2>/dev/null || true
run udevadm settle --timeout=30

for p in "$PART_ESP" "$PART_SWAP" "$PART_ROOT"; do
  for _ in {1..15}; do [[ -b "$p" ]] && break; sleep 1; done
  [[ -b "$p" ]] || die "partição não apareceu: $p"
done

# ------------------------------------------------------------ filesystems ---
run mkfs.fat -F32 -n "$LABEL_ESP" "$PART_ESP"
run mkswap -L "$LABEL_SWAP" "$PART_SWAP"
run mkfs.ext4 -F -L "$LABEL_ROOT" -m 1 "$PART_ROOT"
ok "filesystems criados"

# -------------------------------------------------------------- montagem ----
run mount "$PART_ROOT" /mnt
run mkdir -p /mnt/boot
run mount "$PART_ESP" /mnt/boot
run swapon "$PART_SWAP"

mkdir -p /mnt/boot
ok "montado: $PART_ROOT -> /mnt, $PART_ESP -> /mnt/boot (ESP), swap ativa"

# guarda para as fases seguintes
ROOT_UUID=$(uuid_of "$PART_ROOT")
[[ -n "$ROOT_UUID" ]] && export ROOT_UUID
info "UUID da raiz: ${ROOT_UUID:-<dry-run>}"
