#!/bin/sh
IFACE="phy1-ap0"
RADIO="radio1"

CHANNELS="36 40 44 48"
BANDWIDTHS="HT20 HT40+ VHT80"
TXPOWERS="10 17 23"
NSS_LIST="1 2"
CW_MIN_MAX="7:15 15:31 31:63 63:127"
RTS_MODES="off on"

RUNS=500   # nombre de configurations à exécuter (<= 576 si tu veux éviter les répétitions)

log() { echo "[$(date +%H:%M:%S)] $*"; }

# [Option de robustesse] S'assurer qu'on est dans le dossier du script
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR" || exit 1

## --- 0/ reset propre (inchangé) ---
pkill -f collect_loop3.sh 2>/dev/null
rm -f wifi_log2.jsonl trafic_metrics.jsonl /tmp/last_* /tmp/wifi_conf_queue.txt /tmp/wifi_conf_queue.raw 2>/dev/null
./collect_loop3.sh &

## --- Générer toutes les combinaisons (inchangé, mais en sortie texte) ---
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

# --- Mélanger de façon fiable ---
if command -v shuf >/dev/null 2>&1; then
  shuf /tmp/wifi_conf_queue.raw > /tmp/wifi_conf_queue.txt
else
  # Fallback : utiliser awk+sort (présents sur OpenWrt)
  awk '{srand(); printf "%.10f %s\n", rand(), $0}' /tmp/wifi_conf_queue.raw | sort -n | cut -d" " -f2- > /tmp/wifi_conf_queue.txt
fi

TOTAL=$(wc -l < /tmp/wifi_conf_queue.txt)
log "[INFO] $TOTAL combinaisons générées et mélangées (max unique = 576)."

## --- Boucle principale : on lit 1 config mélangée par run ---
run=1
while [ $run -le $RUNS ]; do
  LINE=$(sed -n "${run}p" /tmp/wifi_conf_queue.txt) || LINE=""
  [ -z "$LINE" ] && { log "[WARN] Plus de combinaisons disponibles. Fin."; break; }

  NSS=$(echo "$LINE" | cut -d, -f1)
  CH=$(echo "$LINE" | cut -d, -f2)
  BW=$(echo "$LINE" | cut -d, -f3)
  TP=$(echo "$LINE" | cut -d, -f4)
  CW=$(echo "$LINE" | cut -d, -f5)
  RTS=$(echo "$LINE" | cut -d, -f6)
  CWMIN=${CW%:*}; CWMAX=${CW#*:}

  # === EXACTEMENT TES COMMANDES ORIGINALES ===

  # Appliquer NSS
  iw dev "$IFACE" set bitrates vht-mcs-5 "${NSS}:0-9" 2>/dev/null

  # Canal + bande passante
  uci set wireless.$RADIO.channel="$CH"
  uci set wireless.$RADIO.htmode="$BW"
  uci commit wireless
  wifi reload
  sleep 5

  # Validation interface UP
  if ! ip link show "$IFACE" | grep -q "state UP"; then
    log " zM-  o  combo CH=$CH BW=$BW invalide  f^r skip"
    run=$((run+1))
    continue
  fi

  # Puissance
  iw phy phy1 set txpower fixed "$((TP*100))" 2>/dev/null || \
    log " zM-  o  driver refuse TX=$TP dBm"

  # CWmin/CWmax
  uci set wireless.default_$RADIO.wmm='1'
  uci set wireless.default_$RADIO.wmm_ac_be="cwmin=$CWMIN cwmax=$CWMAX aifs=2 txop=0"
  uci commit wireless && wifi reload && sleep 1

  # RTS/CTS
  if [ "$RTS" = "on" ]; then
    iw phy phy1 set rts 0
  else
    iw phy phy1 set rts 2347
  fi

  echo "[DEBUG] Exporting NSS=$NSS RTS=$RTS"
  echo "$NSS" > /tmp/current_nss
  echo "$RTS" > /tmp/current_rts

  log "=== Test  CH=$CH BW=$BW NSS=$NSS TX=$TP dBm CW=$CW RTS=$RTS ==="

  # *** UN SEUL appel, comme tu l'as demandé ***
  ./run_iperf_scenarios.sh

  run=$((run+1))
done

pkill -f collect_loop3.sh
log " |^e Campagne terminée  `^s dataset dans wifi_log2.jsonl"


