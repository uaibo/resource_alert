#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
TG_BOT_TOKEN="PASTE_YOUR_TELEGRAM_TOKEN_HERE"
TG_CHAT_ID="PAST_YOUR_CHAT_ID_HERE"

CPU_THRESHOLD=90
MEM_THRESHOLD=90
DISK_THRESHOLD=90
LOAD_THRESHOLD=90   # load % relative to cores

PERSISTENCE_REQUIRED=3        # consecutive bad runs required
COOLDOWN_SECONDS=900          # 15 minutes

COUNT_FILE="/var/tmp/resource_alert.count"
STATE_FILE="/var/tmp/resource_alert.last"
# =========================================

SERVER_IP="$(hostname -I | awk '{print $1}')"
TS="$(TZ=Europe/Tirane date '+%Y-%m-%d %H:%M:%S')"

# ---------- CPU ----------
read -r _ u n s i iw irq sirq st _ _ < /proc/stat
t1=$((u+n+s+i+iw+irq+sirq+st))
i1=$((i+iw))
sleep 1
read -r _ u n s i iw irq sirq st _ _ < /proc/stat
t2=$((u+n+s+i+iw+irq+sirq+st))
i2=$((i+iw))
dt=$((t2-t1))
di=$((i2-i1))
cpu=$(( dt > 0 ? (100*(dt-di))/dt : 0 ))

# ---------- MEM ----------
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem=$(( (100*(mem_total-mem_avail))/mem_total ))

# ---------- DISK ----------
disk=$(df -P / | awk 'NR==2 {gsub("%",""); print $5}')

# ---------- LOAD ----------
cores=$(nproc)
load_raw=$(awk '{print $1}' /proc/loadavg)
load=$(awk -v l="$load_raw" -v c="$cores" 'BEGIN{printf "%d", (l/c)*100}')

# ---------- BREACH ----------
breach=0
(( cpu  >= CPU_THRESHOLD ))  && breach=1
(( mem  >= MEM_THRESHOLD ))  && breach=1
(( disk >= DISK_THRESHOLD )) && breach=1
(( load >= LOAD_THRESHOLD )) && breach=1

# ---------- COUNT ----------
count=0
[[ -f "$COUNT_FILE" ]] && count=$(cat "$COUNT_FILE" || echo 0)

if (( breach == 1 )); then
  count=$((count+1))
  echo "$count" > "$COUNT_FILE"
else
  # full recovery
  echo 0 > "$COUNT_FILE"
  rm -f "$STATE_FILE"
  exit 0
fi

# Not persistent yet
(( count < PERSISTENCE_REQUIRED )) && exit 0

# ---------- INCIDENT ALREADY ALERTED ----------
[[ -f "$STATE_FILE" ]] && exit 0

# ---------- COOLDOWN (edge safety) ----------
now=$(date +%s)
last=0
[[ -f "$STATE_FILE" ]] && last=$(cat "$STATE_FILE" || echo 0)
(( now - last < COOLDOWN_SECONDS )) && exit 0

echo "$now" > "$STATE_FILE"
echo 0 > "$COUNT_FILE"

# ---------- ALERT ----------
MSG="[$TS]
âš ï¸ ${SERVER_IP}

CPU:  ${cpu}%
MEM:  ${mem}%
DISK: ${disk}%
LOAD: ${load}%

Sustained degradation detected."

curl -sS -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TG_CHAT_ID}" \
  --data-urlencode "text=$MSG" \
  >/dev/null
