#!/bin/sh
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
IFACE="phy1-ap0"
JSON_FILE="$BASE_DIR/wifi_metrics2.json"   # <- IMPORTANT: chemin absolu et cohérent avec la loop

# Helpers
safe_num() { [ -n "$1" ] && printf '%s' "$1" || printf 'null'; }
safe_str() { [ -n "$1" ] && printf '"%s"' "$1" || printf 'null'; }

: >"$JSON_FILE"  # vide le fichier

TS=$(date +"%Y-%m-%d %H:%M:%S")
LABEL=$(cat /tmp/current_traffic_label 2>/dev/null || echo "none")
PING_IP="192.168.1.182"

# --- Basic Wi-Fi config --------------------------------------------------
CHANNEL_LINE="$(iw dev "$IFACE" info | grep 'channel' || true)"
CHANNEL="$(echo "$CHANNEL_LINE" | awk '{print $2}')"
FREQ_MHZ="$(echo "$CHANNEL_LINE" | sed -n 's/.*(\([0-9]*\) MHz).*/\1/p')"
BW="$(echo "$CHANNEL_LINE"   | sed -n 's/.*width: \([0-9]*\) MHz.*/\1/p')"
TX_POWER="$(iw dev "$IFACE" info | awk '/txpower/ {print $2; exit}')"

# --- CW min/max via UCI --------------------------------------------------
WMM_BE="$(uci get wireless.default_radio1.wmm_ac_be 2>/dev/null || true)"
CWMIN="$(echo "$WMM_BE" | grep -o 'cwmin=[0-9]*' | cut -d= -f2)"
CWMAX="$(echo "$WMM_BE" | grep -o 'cwmax=[0-9]*' | cut -d= -f2)"

# --- Survey dump ---------------------------------------------------------
SURVEY="$(iw dev "$IFACE" survey dump || true)"
NOISE="$(echo "$SURVEY" | awk '/noise:/ {print $2; exit}')"
ACTIVE_TIME="$(echo "$SURVEY" | awk '/channel active time/ {print $4; exit}')"
BUSY_TIME="$(  echo "$SURVEY" | awk '/channel busy time/  {print $4; exit}')"
BUSY_PERCENT=0
[ "${ACTIVE_TIME:-0}" -gt 0 ] 2>/dev/null && BUSY_PERCENT=$((100*BUSY_TIME/ACTIVE_TIME))

# --- Ping latency --------------------------------------------------------
PING_STATS="$(ping -c4 -W1 "$PING_IP" 2>/dev/null || true)"
LAT_LINE="$(echo "$PING_STATS" | awk -F'=' '/min\/avg\/max/ {print $2}')"
LAT_MIN="$(echo "$LAT_LINE" | cut -d/ -f1 | tr -cd '0-9.')"
LAT_AVG="$(echo "$LAT_LINE" | cut -d/ -f2 | tr -cd '0-9.')"
LAT_MAX="$(echo "$LAT_LINE" | cut -d/ -f3 | tr -cd '0-9.')"

# --- NSS / RTS -----------------------------------------------------------
CUR_NSS="$(cat /tmp/current_nss 2>/dev/null || true)"
CUR_RTS="$(cat /tmp/current_rts 2>/dev/null || true)"

# --- Begin JSON ----------------------------------------------------------
cat >"$JSON_FILE" <<JSON
{
  "timestamp": "$TS",
  "traffic_label": "$LABEL",
  "channel": $(safe_num "$CHANNEL"),
  "frequency_mhz": $(safe_num "$FREQ_MHZ"),
  "bandwidth_mhz": $(safe_num "$BW"),
  "tx_power_dbm": $(safe_num "$TX_POWER"),
  "cwmin": $(safe_num "$CWMIN"),
  "cwmax": $(safe_num "$CWMAX"),
  "noise_floor_dbm": $(safe_num "$NOISE"),
  "channel_busy_percent": $BUSY_PERCENT,
  "nss": $(safe_num "$CUR_NSS"),
  "rts_cts": $(safe_str "$CUR_RTS"),
  "latency_min_ms": $(safe_num "$LAT_MIN"),
  "latency_avg_ms": $(safe_num "$LAT_AVG"),
  "latency_max_ms": $(safe_num "$LAT_MAX"),
  "clients": [
JSON

# --- Loop through clients ------------------------------------------------
FIRST=1
for MAC in $(iw dev "$IFACE" station dump | awk '/^Station/ {print $2}'); do
  echo "Collecting client: $MAC" >&2
  STATS="$(iw dev "$IFACE" station get "$MAC" || true)"

  RSSI="$(     echo "$STATS" | awk '/signal:/ {print $2; exit}' | head -n1)"
  TX_RETRIES="$(echo "$STATS" | awk '/tx retries/ {print $3}' | head -n1)"
  TX_FAILED="$( echo "$STATS" | awk '/tx failed/  {print $3}' | head -n1)"
  TX_RATE="$(   echo "$STATS" | awk '/tx bitrate:/ {print $3}' | head -n1)"
  RX_RATE="$(   echo "$STATS" | awk '/rx bitrate:/ {print $3}' | head -n1)"
  TX_BYTES="$(  echo "$STATS" | awk '/tx bytes:/  {print $3}' | head -n1)"
  RX_BYTES="$(  echo "$STATS" | awk '/rx bytes:/  {print $3}' | head -n1)"
  MCS="$(echo "$STATS" | grep -oE 'HE-MCS [0-9]+|MCS [0-9]+' | awk '{print $2}' | head -n1)"

  [ $FIRST -eq 0 ] && echo "," >>"$JSON_FILE"
  FIRST=0
  cat >>"$JSON_FILE" <<JSON
    {
      "client_mac": "$MAC",
      "signal_rssi_dbm": $(safe_num "$RSSI"),
      "tx_retries": $(safe_num "$TX_RETRIES"),
      "tx_failed": $(safe_num "$TX_FAILED"),
      "tx_bitrate_mbps": $(safe_num "$TX_RATE"),
      "rx_bitrate_mbps": $(safe_num "$RX_RATE"),
      "tx_bytes": $(safe_num "$TX_BYTES"),
      "rx_bytes": $(safe_num "$RX_BYTES"),
      "mcs_index": $(safe_num "$MCS")
    }
JSON
done

# --- Close JSON ----------------------------------------------------------
cat >>"$JSON_FILE" <<JSON
  ]
}
JSON

