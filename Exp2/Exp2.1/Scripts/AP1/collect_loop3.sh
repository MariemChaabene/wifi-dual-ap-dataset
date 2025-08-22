#!/bin/sh
# ------------------------------------------------------------------------------
#  collect_loop3.sh — Fusion Wi‑Fi snapshot + iPerf + TX_DELTA
#  - Cadence alignée sur l’horloge (PERIOD)
#  - Une seule ligne par traffic_label iPerf (évite doublons)
# ------------------------------------------------------------------------------

OUT_FILE="wifi_log2.jsonl"
LAST_LABEL_FILE="/tmp/last_merged_label"

PERIOD=30    # cadence (s)
PHASE=0      # 0 => :00/:30 ; 5 => :05/:35, etc.

# Caler le premier "slot" sur l'horloge
now=$(date +%s)
next=$(( (now / PERIOD) * PERIOD + PHASE ))
[ $next -le $now ] && next=$(( next + PERIOD ))

while true; do
  # Dormir jusqu'au prochain slot exact
  now=$(date +%s); delay=$(( next - now ))
  [ $delay -gt 0 ] && sleep $delay

  start=$(date +%s)

  ###########################################################################
  # 1) Photo Wi‑Fi courante
  ###########################################################################
  ./collect_wifi_metrics_json3.sh   # produit wifi_metrics2.json
  if ! jq -e . wifi_metrics2.json >/dev/null 2>&1; then
      echo "[WARN] JSON Wi‑Fi invalide → ligne ignorée"
      # IMPORTANT : pas de sleep ici -> on laisse le scheduler avancer
      next=$(( next + PERIOD ))
      continue
  fi

  ###########################################################################
  # 2) TX_DELTA via label courant (si présent)
  ###########################################################################
  LABEL=$(cat /tmp/current_traffic_label 2>/dev/null || echo "none")
  TXDELTA_JSON=$(grep "\"traffic_label\":\"$LABEL\"" /root/tx_delta_log.jsonl 2>/dev/null)
  [ -z "$TXDELTA_JSON" ] && TXDELTA_JSON="{}"

  ###########################################################################
  # 3) iPerf récent (<90 s) ET nouveau label
  ###########################################################################
  PERF_JSON="{}"
  NEW_LABEL=""
  if [ -f /tmp/last_iperf_metric.jsonl ]; then
      AGE=$(( $(date +%s) - $(date -r /tmp/last_iperf_metric.jsonl +%s) ))
      if [ "$AGE" -lt 90 ] && jq -e . /tmp/last_iperf_metric.jsonl >/dev/null 2>&1; then
          CUR_LABEL=$(jq -r '.traffic_label // empty' /tmp/last_iperf_metric.jsonl)
          LAST_LABEL="$(cat "$LAST_LABEL_FILE" 2>/dev/null || echo "")"
          if [ -n "$CUR_LABEL" ] && [ "$CUR_LABEL" != "$LAST_LABEL" ]; then
              PERF_JSON=$(cat /tmp/last_iperf_metric.jsonl)
              NEW_LABEL="$CUR_LABEL"
          fi
      fi
  fi

  ###########################################################################
  # 4) Écriture : uniquement s'il y a un NOUVEAU label iPerf
  ###########################################################################
  if [ -n "$NEW_LABEL" ]; then
    jq -c -s '.[0] * .[1] * .[2]' \
          wifi_metrics2.json \
          <(echo "$PERF_JSON") \
          <(echo "$TXDELTA_JSON") \
          >> "$OUT_FILE"
    echo "$NEW_LABEL" > "$LAST_LABEL_FILE"
    echo "[INFO] Nouvelle mesure (label=$NEW_LABEL) écrite dans $OUT_FILE"
  else
    echo "[SKIP] Pas de nouveau label iPerf (ou déjà consommé)."
  fi

  ###########################################################################
  # 5) Avancer d'un slot (PAS de sleep ici)
  ###########################################################################
  next=$(( next + PERIOD ))
done

