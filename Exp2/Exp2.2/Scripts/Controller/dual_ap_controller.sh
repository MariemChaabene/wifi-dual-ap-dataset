#!/bin/bash
set -euo pipefail

AP1="root@192.168.1.10"
AP2="root@192.168.1.2"
REMOTE_DIR="/root"   # <- scripts sur les AP
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
OUT_OK="dataset_dual_ap.jsonl"
OUT_REJ="dataset_dual_ap_rejected.jsonl"
RUNS=1000
TIME_SYNC_TOL=6

wait_line_fast(){ # HOST LABEL [TIMEOUT]
  local HOST="$1" LABEL="$2" TO="${3:-120}" i=0 LINE=""
  while [ $i -lt $TO ]; do
    LINE=$(ssh $SSH_OPTS "$HOST" "cat /tmp/by_label/${LABEL}.json 2>/dev/null || true")
    [ -n "$LINE" ] && { printf '%s\n' "$LINE"; return 0; }
    sleep 2; i=$((i+2))
  done; return 1
}

within_6s(){ # JSON1 JSON2
  local L1="$1" L2="$2"
  local S1=$(echo "$L1" | jq -r '.iperf_start_ts // empty')
  local S2=$(echo "$L2" | jq -r '.iperf_start_ts // empty')
  local E1=$(echo "$L1" | jq -r '.iperf_end_ts   // empty')
  local E2=$(echo "$L2" | jq -r '.iperf_end_ts   // empty')
  [ -z "$S1" -o -z "$S2" -o -z "$E1" -o -z "$E2" ] && return 1
  local s1=$(date -d "$S1" +%s); local s2=$(date -d "$S2" +%s)
  local e1=$(date -d "$E1" +%s); local e2=$(date -d "$E2" +%s)
  local ds=$(( s1>s2 ? s1-s2 : s2-s1 ))
  local de=$(( e1>e2 ? e1-e2 : e2-e1 ))
  [ $ds -le $TIME_SYNC_TOL ] && [ $de -le $TIME_SYNC_TOL ]
}

# S’assurer que collect_loop tourne (optionnel)
ssh $SSH_OPTS "$AP1" "pgrep -f collect_loop_exp2.sh >/dev/null || (nohup $REMOTE_DIR/collect_loop_exp2.sh > $REMOTE_DIR/collect_loop.log 2>&1 &)" || true
ssh $SSH_OPTS "$AP2" "pgrep -f collect_loop_exp2.sh >/dev/null || (nohup $REMOTE_DIR/collect_loop_exp2.sh > $REMOTE_DIR/collect_loop.log 2>&1 &)" || true

for i in $(seq 1 $RUNS); do
  echo "[*] === RUN $i/$RUNS ==="

  # Phase A : CONFIG
  ssh $SSH_OPTS "$AP1" "cd $REMOTE_DIR && ./wifi_test_orch_oneshot.sh" &
  P1=$!
  ssh $SSH_OPTS "$AP2" "cd $REMOTE_DIR && ./wifi_test_orch_oneshot.sh" &
  P2=$!
  wait $P1 || echo "[WARN] AP1 config warning"
  wait $P2 || echo "[WARN] AP2 config warning"

  # Phase B : MESURE
  LABEL="RUN_$(date +%Y%m%d_%H%M%S)_$i"
  echo "[*] LABEL=$LABEL"

  ssh $SSH_OPTS "$AP1" "cd $REMOTE_DIR && ./iperf_with_txdelta.sh '$LABEL'" &
  P1=$!
  ssh $SSH_OPTS "$AP2" "cd $REMOTE_DIR && ./iperf_with_txdelta.sh '$LABEL'" &
  P2=$!
  wait $P1 || echo "[WARN] AP1 iperf warning"
  wait $P2 || echo "[WARN] AP2 iperf warning"

  # Attendre les lignes fusionnées
  L1=$(wait_line_fast "$AP1" "$LABEL" 120 || echo "")
  L2=$(wait_line_fast "$AP2" "$LABEL" 120 || echo "")
  if [ -z "$L1" ] || [ -z "$L2" ]; then
    echo "{\"label\":\"$LABEL\",\"reject\":true,\"reason\":\"missing_line\"}" >> "$OUT_REJ"
    echo "[REJECT] $LABEL : ligne manquante"; continue
  fi

# Synchro ≤ 6 s
if within_6s "$L1" "$L2"; then
  TS=$(date +"%Y-%m-%d %H:%M:%S")
  MERGED=$(jq -c -n --arg ts "$TS" --arg label "$LABEL" \
        --argjson ap1 "$L1" --argjson ap2 "$L2" \
        '{timestamp:$ts, traffic_label:$label, ap1:$ap1, ap2:$ap2}')

  # Vérifie que le JSON est valide avant d’écrire
  echo "$MERGED" | jq -e . >/dev/null
  if [ $? -eq 0 ]; then
    echo "$MERGED" >> "$OUT_OK"
    echo "[OK] fusion écrite -> $OUT_OK"
  else
    echo "[REJECT] $LABEL : JSON invalide lors du merge"
    echo "{\"label\":\"$LABEL\",\"reject\":true,\"reason\":\"merge_invalid_json\"}" >> "$OUT_REJ"
  fi

else
  jq -c -n --arg label "$LABEL" --argjson ap1 "$L1" --argjson ap2 "$L2" \
        '{reject:true, reason:"desync>6s", traffic_label:$label, ap1:$ap1, ap2:$ap2}' >> "$OUT_REJ"
  echo "[REJECT] $LABEL : désynchro > 6 s"
fi

sleep 2

done
