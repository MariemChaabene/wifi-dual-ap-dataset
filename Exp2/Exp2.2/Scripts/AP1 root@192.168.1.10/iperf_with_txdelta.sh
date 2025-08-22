#!/bin/sh
# ------------------------------------------------------------------------------
# iperf_with_txdelta.sh : lance 1 scénario iPerf + calcule TX_DELTA par client
# - Si aucun arg iPerf fourni : tirage aléatoire d'UN scénario (comme avant)
# - Appelle iperf_single_exp2.sh (écrit /tmp/current_traffic_label + /tmp/last_iperf_metric.jsonl)
# - Écrit les deltas dans $BASE_DIR/tx_delta_log.jsonl
# ------------------------------------------------------------------------------

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
IFACE="phy1-ap0"
LABEL="$1"; shift
TXDELTA_FILE="$BASE_DIR/tx_delta_log.jsonl"

# --- Choix du scénario (si aucun arg n'est passé) ---
if [ $# -eq 0 ]; then
  CANDIDATES='
-P 1 -t 10
-P 2 -t 10
-P 4 -t 10
-P 8 -t 10
-P 16 -t 10
-P 1 -w 512K -t 10
-P 1 -w 1M   -t 10
-P 1 -w 2M   -t 10
-P 1 -w 4M   -t 10
-u -b 5M   -t 10
-u -b 10M  -t 10
-u -b 50M  -t 10
-u -b 100M -t 10
-u -b 200M -t 10
-u -b 400M -t 10
'
  if command -v shuf >/dev/null 2>&1; then
    # IMPORTANT: conserver les retours à la ligne -> "$CANDIDATES"
    IPERF_ARGS=$(printf "%s\n" "$CANDIDATES" | awk 'NF' | shuf | head -n1)
  else
    IPERF_ARGS=$(printf "%s\n" "$CANDIDATES" | awk 'NF{print rand() "\t" $0}' | sort -n | head -n1 | cut -f2-)
  fi
else
  IPERF_ARGS="$*"
fi

# Durée pour l'estimation (défaut 10s si -t absent)
DUR=$(printf "%s\n" "$IPERF_ARGS" | awk 'match($0,/-t[[:space:]]*([0-9]+)/,m){print m[1]}' || true)
[ -z "$DUR" ] && DUR=10

echo "[RUN] LABEL=$LABEL | iperf args: $IPERF_ARGS"

# --- TX bytes AVANT ---
> /tmp/tx_before.log
for MAC in $(iw dev "$IFACE" station dump | awk '/^Station/ {print $2}'); do
  TXB=$(iw dev "$IFACE" station get "$MAC" | awk '/tx bytes:/ {print $3}')
  [ -n "$TXB" ] && echo "$MAC:$TXB" >> /tmp/tx_before.log
done

# --- iPerf (déclenche le label et /tmp/last_iperf_metric.jsonl) ---
# iperf_single_exp2.sh ajoute -t 10 si absent, et écrit /tmp/current_traffic_label
"$BASE_DIR/iperf_single_exp2.sh" "$LABEL" $IPERF_ARGS

# --- TX bytes APRES + delta ---
TS=$(date +"%Y-%m-%d %H:%M:%S")
for MAC in $(iw dev "$IFACE" station dump | awk '/^Station/ {print $2}'); do
  TXA=$(iw dev "$IFACE" station get "$MAC" | awk '/tx bytes:/ {print $3}')
  TXB=$(grep "^$MAC:" /tmp/tx_before.log | cut -d: -f2)
  [ -z "$TXB" ] && TXB=0

  DELTA=$((TXA - TXB))
  [ "$DELTA" -lt 0 ] && DELTA=0

  EST=$(( DELTA * 8 / DUR ))  # bps approx

  printf '{"timestamp":"%s","traffic_label":"%s","client_mac":"%s","tx_delta_bytes":%s,"estimated_throughput_bps":%s}\n' \
    "$TS" "$LABEL" "$MAC" "$DELTA" "$EST" >> "$TXDELTA_FILE"
done

