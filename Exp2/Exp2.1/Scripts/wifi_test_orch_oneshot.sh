#!/bin/sh
# ------------------------------------------------------------------------------
# wifi_test_orch_oneshot.sh  (PHASE A = CONFIG SEULEMENT)
# - Génère (si besoin) et mélange la liste des configurations Wi-Fi
# - Dépile UNE configuration (sans répétition)
# - Applique la config sur l'AP (1 seul wifi reload)
# - Ne lance PAS iPerf (Phase B faite par le contrôleur)
# ------------------------------------------------------------------------------

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR"

IFACE="phy1-ap0"
RADIO="radio1"
PHY="phy1"   # adapte si besoin (ex: phy0/phy1)

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- LOCK : éviter 2 runs concurrents ---
if ! mkdir /tmp/wto.lock 2>/dev/null; then
  echo "[ERR] another run in progress"
  exit 2
fi
trap 'rmdir /tmp/wto.lock' EXIT

# --- Générer la queue si absente (avec SHUF + fallback portable) ---
if [ ! -s /tmp/wifi_conf_queue.txt ]; then
  CHANNELS="36 40 44 48"
  BANDWIDTHS="HT20 HT40+ VHT80"
  TXPOWERS="10 17 23"
  NSS_LIST="1 2"
  CW_MIN_MAX="7:15 15:31 31:63 63:127"
  RTS_MODES="off on"

  {
    for NSS in $NSS_LIST; do
      for CH in $CHANNELS; do
        for BW in $BANDWIDTHS; do
          for TP in $TXPOWERS; do
            for CW in $CW_MIN_MAX; do
              for RTS in $RTS_MODES; do
                echo "$NSS,$CH,$BW,$TP,$CW,$RTS"
              done
            done
          done
        done
      done
    done
  } > /tmp/wifi_conf_queue.raw

  if command -v shuf >/dev/null 2>&1; then
    shuf /tmp/wifi_conf_queue.raw > /tmp/wifi_conf_queue.txt
  else
    awk '{srand(); printf "%.10f %s\n", rand(), $0}' /tmp/wifi_conf_queue.raw \
      | sort -n | cut -d" " -f2- > /tmp/wifi_conf_queue.txt
  fi
fi

# --- Pop 1 ligne (la liste a déjà été mélangée) ---
LINE="$(head -n1 /tmp/wifi_conf_queue.txt || true)"
[ -z "$LINE" ] && { log "[WARN] queue empty"; exit 3; }
# Retirer la ligne consommée
tail -n +2 /tmp/wifi_conf_queue.txt > /tmp/wifi_conf_queue.tmp && mv /tmp/wifi_conf_queue.tmp /tmp/wifi_conf_queue.txt

# --- Parse ---
NSS="$(echo "$LINE" | cut -d, -f1)"
CH="$(  echo "$LINE" | cut -d, -f2)"
BW="$(  echo "$LINE" | cut -d, -f3)"
TP="$(  echo "$LINE" | cut -d, -f4)"
CW="$(  echo "$LINE" | cut -d, -f5)"
RTS="$( echo "$LINE" | cut -d, -f6)"
CWMIN=${CW%:*}
CWMAX=${CW#*:}

log "CFG: CH=$CH BW=$BW NSS=$NSS TX=$TP dBm CW=$CWMIN:$CWMAX RTS=$RTS"

# --- Appliquer la config Wi-Fi (1 seul reload) ---

# 1) UCI en batch → 1 commit, 1 reload
uci -q batch <<EOF
set wireless.$RADIO.channel='$CH'
set wireless.$RADIO.htmode='$BW'
set wireless.default_$RADIO.wmm='1'
set wireless.default_$RADIO.wmm_ac_be='cwmin=$CWMIN cwmax=$CWMAX aifs=2 txop=0'
commit wireless
EOF

wifi reload
sleep 5

# Sanity : interface UP
if ! ip link show "$IFACE" | grep -q "state UP"; then
  echo "[ERR] interface $IFACE down after reload"
  exit 4
fi

# 2) Réglages runtime (pas de reload nécessaire)
# NSS (si supporté par le driver)
iw dev "$IFACE" set bitrates vht-mcs-5 "${NSS}:0-9" 2>/dev/null || true
# Puissance d'émission (dBm)
iw phy "$PHY" set txpower fixed "$((TP*100))" 2>/dev/null || true
# RTS/CTS
if [ "$RTS" = "on" ]; then
  iw phy "$PHY" set rts 0
else
  iw phy "$PHY" set rts 2347
fi

# Exports pour tracing / collect
echo "$NSS" > /tmp/current_nss
echo "$RTS" > /tmp/current_rts

# Trace (facultatif mais utile)
TS=$(date +"%Y-%m-%d %H:%M:%S")
printf '{"timestamp":"%s","applied_config":{"nss":"%s","ch":"%s","bw":"%s","tx_dbm":"%s","cwmin":"%s","cwmax":"%s","rts":"%s"}}\n' \
  "$TS" "$NSS" "$CH" "$BW" "$TP" "$CWMIN" "$CWMAX" "$RTS" > /tmp/last_applied_config.json

log "CONFIG DONE."
exit 0

