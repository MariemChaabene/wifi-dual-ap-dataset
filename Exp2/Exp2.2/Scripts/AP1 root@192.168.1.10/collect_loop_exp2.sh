#!/bin/sh
# ------------------------------------------------------------------------------
# collect_loop_exp2.sh : Fusion Wi-Fi + iPerf + TX_DELTA (1 ligne par label)
# - Tourne en continu sur chaque AP
# - Écrit dans wifi_log2.jsonl et /tmp/by_label/<LABEL>.json (écriture atomique)
# ------------------------------------------------------------------------------

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_FILE="$BASE_DIR/wifi_log2.jsonl"
LAST_LABEL_FILE="/tmp/last_merged_label"
PERIOD=30
AP_ID="$(cat /etc/ap_id 2>/dev/null || echo "AP?")"

METRICS_JSON="$BASE_DIR/wifi_metrics2.json"    # produit par collect_wifi_metrics_json3.sh
TXDELTA_FILE="$BASE_DIR/tx_delta_log.jsonl"    # alimenté par iperf_with_txdelta.sh
PERF_FILE="/tmp/last_iperf_metric.jsonl"       # alimenté par iperf_single_exp2.sh

# Nettoyer les anciens fichiers temporaires
rm -f /tmp/last_merged_label /tmp/by_label/*.json 2>/dev/null
mkdir -p /tmp/by_label

while true; do
  ###########################################################################
  # 1) Snapshot Wi-Fi → METRICS_JSON
  ###########################################################################
  "$BASE_DIR/collect_wifi_metrics_json3.sh"
  if ! [ -s "$METRICS_JSON" ] || ! jq -e . "$METRICS_JSON" >/dev/null 2>&1; then
    echo "[WARN] JSON Wi-Fi invalide ou manquant → skip"
    sleep "$PERIOD"; continue
  fi

  ###########################################################################
  # 2) Label courant + éviter doublons
  ###########################################################################
  LABEL="$(cat /tmp/current_traffic_label 2>/dev/null || echo "none")"
  LAST_LABEL="$(cat "$LAST_LABEL_FILE" 2>/dev/null || echo "none")"
  if [ "$LABEL" = "none" ] || [ "$LABEL" = "$LAST_LABEL" ]; then
    sleep "$PERIOD"; continue
  fi

  ###########################################################################
  # 3) TX_DELTA pour ce label
  ###########################################################################
  TXDELTA_JSON="$(grep -F "\"traffic_label\":\"$LABEL\"" "$TXDELTA_FILE" 2>/dev/null | tail -n1)"
  if ! printf '%s' "${TXDELTA_JSON:-}" | jq -e . >/dev/null 2>&1; then
    TXDELTA_JSON="{}"
  fi
  printf '%s' "$TXDELTA_JSON" > /tmp/txd.json

  ###########################################################################
  # 3.5) iPerf : capture anticipée si iPerf encore en cours
  ###########################################################################
  IPERF_RUNNING_LABEL="$(cat /tmp/iperf_running.label 2>/dev/null || echo "")"

  if [ -n "$IPERF_RUNNING_LABEL" ] && [ "$IPERF_RUNNING_LABEL" = "$LABEL" ]; then
    echo "[INFO] iPerf en cours pour $LABEL → capture anticipée"
  else
    # Sinon, vérifier la fin d'iPerf comme avant
    if [ ! -s "$PERF_FILE" ] || ! jq -e . "$PERF_FILE" >/dev/null 2>&1; then
      sleep "$PERIOD"; continue
    fi
    CUR_LABEL="$(jq -r '.traffic_label // empty' "$PERF_FILE")"
    if [ "$CUR_LABEL" != "$LABEL" ]; then
      sleep "$PERIOD"; continue
    fi
    AGE=$(( $(date +%s) - $(date -r "$PERF_FILE" +%s) ))
    if [ "$AGE" -gt 90 ]; then
      echo "[WARN] Artefact iPerf trop ancien (AGE=${AGE}s) → skip"
      sleep "$PERIOD"; continue
    fi
  fi

  PERF_JSON="$(cat "$PERF_FILE" 2>/dev/null || echo '{}')"

  ###########################################################################
  # ✅ Validation des composants
  ###########################################################################
  echo "$PERF_JSON" | jq -e . >/dev/null 2>&1 || { echo "[ERR] PERF_JSON invalide → skip"; sleep "$PERIOD"; continue; }
  jq -e . "$METRICS_JSON" >/dev/null 2>&1 || { echo "[ERR] METRICS_JSON invalide → skip"; sleep "$PERIOD"; continue; }
  jq -e . /tmp/txd.json >/dev/null 2>&1 || { echo "[ERR] TXDELTA_JSON invalide → skip"; sleep "$PERIOD"; continue; }

  ###########################################################################
  # 4) Fusion Wi-Fi + TX_DELTA + iPerf (écriture atomique)
  ###########################################################################
  MERGED_JSON="$(
    jq -c -s \
      --arg ap "$AP_ID" \
      --arg lbl "$LABEL" \
      --argjson perf "$PERF_JSON" \
      '($perf + {"ap":$ap, "traffic_label":$lbl, "wifi":.[0], "tx_delta":.[1]})' \
      "$METRICS_JSON" /tmp/txd.json
  )"

  # Vérification finale du JSON fusionné
  echo "$MERGED_JSON" | jq -e . >/dev/null 2>&1 || { echo "[ERR] MERGED_JSON invalide → skip"; sleep "$PERIOD"; continue; }

  # ✅ Tout est bon : écriture
  printf '%s\n' "$MERGED_JSON" >> "$OUT_FILE"

  TMPF="/tmp/by_label/.${LABEL}.json.tmp"
  printf '%s\n' "$MERGED_JSON" > "$TMPF"
  mv -f "$TMPF" "/tmp/by_label/${LABEL}.json"

  printf '%s\n' "$LABEL" > "$LAST_LABEL_FILE"
  echo "[INFO] ✅ Nouvelle ligne fusionnée ajoutée pour label=$LABEL"

  sleep "$PERIOD"
done

