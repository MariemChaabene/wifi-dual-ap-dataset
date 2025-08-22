#!/bin/bash

IFACE="phy1-ap0"


# --- Générer les scénarios ---
SCENARIOS=()

# TCP multi-flux
for P in 1 2 4 8 16; do
  SCENARIOS+=("-P $P")
done

# TCP avec tailles de fenêtres
for W in 512K 1M 2M 4M; do
  SCENARIOS+=("-P 1 -w $W")
done

# UDP avec débits
for B in 5 10 50 100 200 400; do
  SCENARIOS+=("-u -b ${B}M")
done

# --- Mélanger et sélectionner 20 scénarios ---
SELECTED=$(printf "%s\n" "${SCENARIOS[@]}" | shuf | head -n 3)

# --- Lancer les tests ---
SCENARIO_ID=1
while read -r ARGS; do
  LABEL="TEST${SCENARIO_ID}_$(date +%Y%m%d_%H%M%S)"
echo "[RUN] $LABEL => iperf3 $ARGS"


  # --- Lire tx_bytes avant le test pour chaque client ---
  > /tmp/tx_before.log
  for CLIENT_MAC in $(iw dev "$IFACE" station dump | awk '/^Station/ {print $2}'); do
    TX_BEFORE=$(iw dev "$IFACE" station get "$CLIENT_MAC" | awk '/tx bytes:/ {print $3}')
    echo "$CLIENT_MAC:$TX_BEFORE" >> /tmp/tx_before.log
  done

# --- Lancer le test ---
  ./iperf_single.sh "$LABEL" $ARGS

  # --- Lire tx_bytes après le test et calculer delta ---
  for CLIENT_MAC in $(iw dev "$IFACE" station dump | awk '/^Station/ {print $2}'); do
    TX_AFTER=$(iw dev "$IFACE" station get "$CLIENT_MAC" | awk '/tx bytes:/ {print $3}')
    TX_BEFORE=$(grep "$CLIENT_MAC" /tmp/tx_before.log | cut -d: -f2)
    if [ -n "$TX_BEFORE" ] && [ -n "$TX_AFTER" ]; then
      TX_DELTA=$((TX_AFTER - TX_BEFORE))
      THR_TX_BYTES=$((TX_DELTA * 8 / 10))
      echo "[INFO] Client: $CLIENT_MAC | TX_DELTA=$TX_DELTA bytes | Est. throughput=$THR_TX_BYTES bps"
      printf '{"traffic_label":"%s","client_mac":"%s","tx_delta_bytes":%s,"estimated_throughput_bps":%s}\n' \
        "$LABEL" "$CLIENT_MAC" "$TX_DELTA" "$THR_TX_BYTES" >> /root/tx_delta_log.jsonl
    fi
  done

  echo "[WAIT] 65 seconds..."
  sleep 65
  SCENARIO_ID=$((SCENARIO_ID + 1))
done <<< "$SELECTED"
