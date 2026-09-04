#!/bin/bash
# HNdi bench — simulate a degrading link to validate jitter/dropout recovery.
# Impairs ONLY the NDI flow (a given port), so the local API (8791), DevTools
# (9222) and your ssh session are untouched. Root required (tc / iptables).
#
#   netem.sh jitter <delay_ms> <jitter_ms> [iface] [port]   # add latency + jitter
#   netem.sh loss   <percent>              [iface] [port]   # drop a % of packets
#   netem.sh flap   <delay> <jitter> <loss> [iface] [port]  # jitter + loss together
#   netem.sh drop   <seconds>              [ip]    [port]   # full outage for N s, then restore
#   netem.sh status                                          # show active impairments
#   netem.sh clear                                           # remove everything
#
# Defaults: iface=lo, port=5961 (a loopback NDI sender). For a REMOTE sender, run
# jitter/loss on the SENDER's egress iface (needs root there), or use `drop` here
# (it blocks the NDI port inbound, which works for any source).
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
CMD="${1:-status}"; shift || true

qdisc_setup() {  # $1 iface, $2 port, then netem args
  local iface="$1" port="$2"; shift 2
  tc qdisc del dev "$iface" root 2>/dev/null
  tc qdisc add dev "$iface" root handle 1: prio
  tc qdisc add dev "$iface" parent 1:3 handle 30: netem "$@"
  # send only the NDI port (either direction) through the netem band
  tc filter add dev "$iface" parent 1: protocol ip u32 match ip dport "$port" 0xffff flowid 1:3
  tc filter add dev "$iface" parent 1: protocol ip u32 match ip sport "$port" 0xffff flowid 1:3
  echo "impairing $iface port $port: netem $*"
}

case "$CMD" in
  jitter) qdisc_setup "${3:-lo}" "${4:-5961}" delay "${1:?delay_ms}"ms "${2:-0}"ms distribution normal ;;
  loss)   qdisc_setup "${2:-lo}" "${3:-5961}" loss "${1:?percent}"% ;;
  flap)   qdisc_setup "${4:-lo}" "${5:-5961}" delay "${1:?delay}"ms "${2:-0}"ms loss "${3:-0}"% distribution normal ;;
  drop)
    SEC="${1:?seconds}"; IP="${2:-}"; PORT="${3:-5961}"
    SRC=""; [ -n "$IP" ] && SRC="-s $IP"
    echo "blackholing NDI port $PORT ${IP:+from $IP} for ${SEC}s…"
    for pr in tcp udp; do iptables -I INPUT -p $pr $SRC --sport "$PORT" -j DROP; iptables -I INPUT -p $pr $SRC --dport "$PORT" -j DROP; done
    sleep "$SEC"
    for pr in tcp udp; do iptables -D INPUT -p $pr $SRC --sport "$PORT" -j DROP 2>/dev/null; iptables -D INPUT -p $pr $SRC --dport "$PORT" -j DROP 2>/dev/null; done
    echo "restored."
    ;;
  status)
    echo "== tc (lo) =="; tc qdisc show dev lo | sed 's/^/  /'
    echo "== iptables DROP rules =="; iptables -S INPUT 2>/dev/null | grep -- '-j DROP' | sed 's/^/  /' || echo "  (none)"
    ;;
  clear)
    tc qdisc del dev lo root 2>/dev/null && echo "tc cleared" || echo "no tc on lo"
    for l in $(seq 1 20); do iptables -S INPUT 2>/dev/null | grep -- '--sport 5961\|--dport 5961' | head -1 | sed 's/^-I/-D/;s/^-A/-D/' | xargs -r iptables 2>/dev/null || break; done
    echo "iptables NDI drops flushed"
    ;;
  *) echo "usage: $0 {jitter|loss|flap|drop|status|clear} …"; exit 1 ;;
esac
