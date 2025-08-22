#!/bin/bash
##############################################################################
#  iperf_server_listener.sh : lance iperf3 en mode serveur, enchaîne plusieurs
#  tests, extrait les métriques et écrit un JSONL par mesure dans trafic_metrics_server.jsonl.
##############################################################################

OUT="/tmp/trafic_metrics_server.jsonl"
TMP="/tmp/iperf_server_debug.json"

echo "[INFO] Serveur iPerf prêt à capturer plusieurs tests..."

while true; do
  echo "[INFO] En attente d’un nouveau test iPerf3..."
  iperf3 -s -1 -J > "$TMP"

  # Vérifier le JSON
  if ! jq -e . "$TMP" >/dev/null 2>&1; then
      echo "[ERREUR] JSON invalide dans $TMP" >&2
      continue
  fi

  # Extraire le label depuis --extra-data ou mettre NO_LABEL
  LABEL=$(jq -r '.extra_data // "NO_LABEL"' "$TMP")

  START_TS=$(date +"%Y-%m-%d %H:%M:%S")

  # Extraire protocole, streams et débit
  PROTO=$(jq -r '.start.test_start.protocol' "$TMP")
  STRMS=$(jq '.start.test_start.num_streams' "$TMP")
  THR=$(jq '.end.sum_received.bits_per_second' "$TMP")
  LOSS=0
  JITT=null

  if [ "$PROTO" = "UDP" ]; then
      LOSS=$(jq '.end.sum.lost_percent' "$TMP")
      JITT=$(jq '.end.sum.jitter_ms' "$TMP")
  fi
  # Écrire une ligne JSONL compacte
  printf '{"timestamp":"%s","traffic_label":"%s",' "$START_TS" "$LABEL" >> "$OUT"
  printf '"proto":"%s","streams":%s,' "$PROTO" "$STRMS" >> "$OUT"
  printf '"throughput_received_bps":%s,"loss_pct":%s,"jitter_ms":%s}\n' \
         "${THR:-null}" "${LOSS:-null}" "${JITT:-null}" >> "$OUT"

  echo "[OK] Mesure enregistrée avec label $LABEL dans $OUT"
done
