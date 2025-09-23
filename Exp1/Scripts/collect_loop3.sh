#!/bin/sh
# ------------------------------------------------------------------------------
#  collect_loop3.sh  assemble Wi-Fi snapshot + iPerf métriques + TX_DELTA
# ------------------------------------------------------------------------------

OUT_FILE="wifi_log2.jsonl"

while true; do
  ###########################################################################
  # 1) Prendre la photo Wi-Fi courante
  ###########################################################################
  ./collect_wifi_metrics_json3.sh          # écrit wifi_metrics2.json
  if ! jq -e . wifi_metrics2.json >/dev/null 2>&1; then
      echo "[WARN] JSON Wi-Fi invalide  f^r ligne ignorée"
      sleep 30;  continue
  fi

  ###########################################################################
  # 2) Retrouver le delta octets (le label sert de clé)
  ###########################################################################
  LABEL=$(cat /tmp/current_traffic_label 2>/dev/null || echo "none")
  TXDELTA_JSON=$(grep "\"traffic_label\":\"$LABEL\"" /root/tx_delta_log.jsonl 2>/dev/null)
  [ -z "$TXDELTA_JSON" ] && TXDELTA_JSON="{}"           # si absent  f^r objet vide

  ###########################################################################
  # 3) Vérifier la présence d un résultat iPerf récent (<70 s)
  ###########################################################################
  PERF_JSON="{}"            # valeur par défaut si rien de frais
  if [ -f /tmp/last_iperf_metric.jsonl ]; then
      AGE=$(( $(date +%s) - $(date -r /tmp/last_iperf_metric.jsonl +%s) ))
      if [ "$AGE" -lt 70 ] && jq -e . /tmp/last_iperf_metric.jsonl >/dev/null 2>&1; then
          PERF_JSON=$(cat /tmp/last_iperf_metric.jsonl)
      fi
  fi

###########################################################################
  # 4) Fusion compacte : Wi-Fi  *  iPerf  *  TX_DELTA
  #    (nss et rts_cts sont déjà dans le JSON Wi-Fi)
  ###########################################################################
  jq -c -s '.[0] * .[1] * .[2]' \
        wifi_metrics2.json \
        <(echo "$PERF_JSON") \
        <(echo "$TXDELTA_JSON") \
        >> "$OUT_FILE"

  echo "[INFO] Ligne écrite dans $OUT_FILE"
  sleep 30
done
