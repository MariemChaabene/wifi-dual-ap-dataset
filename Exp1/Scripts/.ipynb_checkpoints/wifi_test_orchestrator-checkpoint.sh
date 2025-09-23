#!/bin/sh
IFACE="phy1-ap0"         # le nom de l `^yinterface AP
RADIO="radio1"           # le bloc UCI concern_

CHANNELS="36 40 44 48"
BANDWIDTHS="HT20 HT40+ VHT80"

TXPOWERS="10 17 23"             # en dBm
NSS_LIST="1 2"                  # flux spatiaux
CW_MIN_MAX="7:15 15:31 31:63 63:127"
RTS_MODES="off on"              # 2347 ou 0

log() { echo "[$(date +%H:%M:%S)] $*"; }

## --- 0/ reset propre
pkill -f collect_loop3.sh 2>/dev/null
rm -f wifi_log2.jsonl trafic_metrics.jsonl /tmp/last_* 2>/dev/null

./collect_loop3.sh &

## --- 1/ boucles imbriqu_es
for NSS in $NSS_LIST; do
  iw dev "$IFACE" set bitrates vht-mcs-5 "${NSS}:0-9" 2>/dev/null

  for CH in $CHANNELS; do
    uci set wireless.$RADIO.channel="$CH"
    uci commit wireless
    wifi reload
    sleep 2

    for BW in $BANDWIDTHS; do
      uci set wireless.$RADIO.htmode="$BW"
      uci commit wireless
      wifi reload
      sleep 2
      # --- validation : l `^yAP est-il mont_ ?
      if ! ip link show "$IFACE" | grep -q "state UP"; then
        log " zM-  o  combo CH=$CH BW=$BW invalide  f^r skip"
        continue   # passe _ la largeur suivante
      fi

      for TP in $TXPOWERS; do
        iw phy phy1 set txpower fixed "$((TP*100))" 2>/dev/null || \
          log " zM-  o  driver refuse TX=$TP dBm"

        for CW in $CW_MIN_MAX; do
                  CWMIN=${CW%:*}; CWMAX=${CW#*:}
                uci set wireless.default_$RADIO.wmm='1'                                    #  zM-  o Active WMM
                uci set wireless.default_$RADIO.wmm_ac_be="cwmin=$CWMIN cwmax=$CWMAX aifs=2 txop=0"
                uci commit wireless && wifi reload && sleep 1


          for RTS in $RTS_MODES; do
            if [ "$RTS" = "on" ]; then
              iw phy phy1 set rts 0
            else
              iw phy phy1 set rts 2347
            fi
                echo "[DEBUG] Exporting NSS=$NSS RTS=$RTS"
                # --- publier le contexte courant ---
                echo "$NSS" > /tmp/current_nss
                echo "$RTS" > /tmp/current_rts


            log "=== Test  CH=$CH BW=$BW NSS=$NSS TX=$TP dBm CW=$CW RTS=$RTS ==="
            ./run_iperf_scenarios.sh      #  fM-3 contient d_j_ les _ sleep _
          done
        done
      done
    done
  done
done

pkill -f collect_loop3.sh
log " |^e Campagne termin_e  `^s dataset dans wifi_log2.jsonl"
