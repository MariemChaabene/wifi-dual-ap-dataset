#!/bin/sh
##############################################################################
# iperf_single_exp2.sh :
#   Lance iPerf3, extrait les métriques, écrit 1 ligne JSONL dans trafic_metrics.jsonl
#   et met la dernière ligne dans /tmp/last_iperf_metric.jsonl
#   Usage : ./iperf_single_exp2.sh <label> "iperf_options..."
##############################################################################

set -e

SERVER_IP="192.168.1.182"       
LABEL="$1"; shift
OPTS="$@"
OUT="trafic_metrics.jsonl"
TMP="/tmp/iperf_debug.json"

# Début
IPERF_START_TS=$(date +"%Y-%m-%d %H:%M:%S")
echo "$LABEL" > /tmp/current_traffic_label
echo "$LABEL" > /tmp/iperf_running.label

# Ajouter -t 10 si non précisé
echo "$OPTS" | grep -q '\-t' || OPTS="$OPTS -t 10"

# Lancer iPerf3 (JSON)
iperf3 -c "$SERVER_IP" --json --extra-data "$LABEL" -i 1 $OPTS > "$TMP"
if [ $? -ne 0 ] || ! jq -e . "$TMP" >/dev/null 2>&1; then
    echo "[ERROR] iPerf3 a échoué pour le label $LABEL" >&2
    rm -f /tmp/iperf_running.label
    exit 1
fi

IPERF_END_TS=$(date +"%Y-%m-%d %H:%M:%S")


# iPerf terminé : supprimer le flag "running"
rm -f /tmp/iperf_running.label

# Déterminer protocole/streams/udp rate/window
case " $OPTS " in *" -u "*) PROTO="UDP" ;; *) PROTO="TCP" ;; esac
STRMS=$(echo "$OPTS" | grep -oE '\-P ?[0-9]+' | grep -oE '[0-9]+' | head -n1)
[ -z "$STRMS" ] && STRMS=1
URATE=$(echo "$OPTS" | grep -oE '\-b ?[0-9]+[KMG]?' | grep -oE '[0-9]+[KMG]?' | head -n1)
WIN=$(echo "$OPTS"   | grep -oE '\-w ?[0-9]+[KMG]?' | grep -oE '[0-9]+[KMG]?' | head -n1)
[ -z "$URATE" ] && URATE=""
[ -z "$WIN" ] && WIN=""

# Extraire métriques iPerf du JSON (valeurs numériques)
if [ "$PROTO" = "UDP" ]; then
    THR=$( jq '.end.sum.bits_per_second'      "$TMP" )
    LOSS=$(jq '.end.sum.lost_percent'         "$TMP" )
    JITT=$(jq '.end.sum.jitter_ms'            "$TMP" )
else
    THR=$( jq '.end.sum_sent.bits_per_second' "$TMP" )
    LOSS=0
    JITT=null
fi

# Construire la ligne JSON (comme avant, avec printf) + timestamps début/fin
LINE=$(printf '{"traffic_label":"%s","iperf_start_ts":"%s","iperf_end_ts":"%s","proto":"%s","streams":%s,"udp_rate":"%s","tcp_window":"%s","throughput_bps":%s,"loss_pct":%s,"jitter_ms":%s}\n' \
       "$LABEL" "$IPERF_START_TS" "$IPERF_END_TS" "$PROTO" "$STRMS" "$URATE" "$WIN" \
       "${THR:-null}" "${LOSS:-null}" "${JITT:-null}")

# Append et export
printf '%s' "$LINE" >> "$OUT"
printf '%s' "$LINE" > /tmp/last_iperf_metric.jsonl

