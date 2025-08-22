#!/bin/sh
##############################################################################
#  iperf_single.sh : Lance un run iPerf3, extrait les métriques, écrit 1 ligne
#                    JSONL dans trafic_metrics.jsonl et garde un fichier debug.
#  Usage :  ./iperf_single.sh label "iperf_options..."
##############################################################################

SERVER_IP="192.168.1.109"        # Adresse IP de la machine qui tourne 'iperf3 -s'
LABEL="$1"; shift                # ex. TEST1
OPTS="$@"                        # ex. -P 4 -w 4M ou -u -b 50M
OUT="trafic_metrics.jsonl"
TMP="/tmp/iperf_debug.json"      # fichier debug JSON complet

START_TS=$(date +"%Y-%m-%d %H:%M:%S")

# Afficher le label pour le collecteur Wi-Fi
echo "$LABEL" > /tmp/current_traffic_label

##############################################################################
#  =^tM-' Ajout de -t 10 si non précisé
##############################################################################
echo "$OPTS" | grep -q '\-t' || OPTS="$OPTS -t 10"


##############################################################################
#  vM-6 o Lancer iPerf3
##############################################################################
# Lancer iPerf3

iperf3 -c "$SERVER_IP" \
       --json \
       --extra-data "$LABEL" \
       -i 1 $OPTS \
       > "$TMP"

if [ $? -ne 0 ]; then
    echo "$(date)  }^l iPerf3 failed for label $LABEL (voir $TMP)" >&2
    exit 1
fi

#  |^t o Valider le JSON
if ! jq -e . "$TMP" >/dev/null 2>&1; then
    echo "$(date)  }^l JSON invalide pour label $LABEL (voir $TMP)" >&2
    exit 1
fi

##############################################################################
#  =^t^m Extraire les infos utiles
##############################################################################
# Protocole
case " $OPTS " in
  *" -u "*) PROTO="UDP" ;;
           *) PROTO="TCP" ;;
esac

# Nombre de flux TCP
STRMS=$(echo "$OPTS" | grep -oE '\-P ?[0-9]+' | grep -oE '[0-9]+')
[ -z "$STRMS" ] && STRMS=1

# Débit UDP
URATE=$(echo "$OPTS" | grep -oE '\-b ?[0-9]+[KMG]?' | grep -oE '[0-9]+[KMG]?')
[ -z "$URATE" ] && URATE=""

# Fenêtre TCP
WIN=$(echo "$OPTS" | grep -oE '\-w ?[0-9]+[KMG]?' | grep -oE '[0-9]+[KMG]?')
[ -z "$WIN" ] && WIN=""

# Métriques à extraire
if [ "$PROTO" = "UDP" ]; then
    THR=$( jq '.end.sum.bits_per_second'   "$TMP" )
    LOSS=$(jq '.end.sum.lost_percent'      "$TMP" )
    JITT=$(jq '.end.sum.jitter_ms'         "$TMP" )
else
    THR=$( jq '.end.sum_sent.bits_per_second' "$TMP" )
    LOSS=0
    JITT=null
fi

##############################################################################
#  =^s^}  icrire 1 ligne JSONL compacte
##############################################################################
printf '{"timestamp":"%s","traffic_label":"%s",'   "$START_TS" "$LABEL" >> "$OUT"
printf '"proto":"%s","streams":%s,'                "$PROTO" "$STRMS"    >> "$OUT"
printf '"udp_rate":"%s","tcp_window":"%s",'        "$URATE" "$WIN"      >> "$OUT"
printf '"throughput_bps":%s,"loss_pct":%s,"jitter_ms":%s}\n' \
       "${THR:-null}" "${LOSS:-null}" "${JITT:-null}" >> "$OUT"

# Copie dernière ligne vers /tmp pour inspection rapide
tail -n 1 "$OUT" > /tmp/last_iperf_metric.jsonl

# Facultatif : supprime le fichier de debug
# rm "$TMP"
