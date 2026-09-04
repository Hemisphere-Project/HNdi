#!/bin/bash
# HNdi — Phase 0 bench. Gets an NDI stream onto /dev/video10 on ONE box, with a
# software NDI sender so no Resolume is needed. Idempotent steps; run all or one:
#
#   ./phase0.sh                 # deps ndi plugin loopback run
#   ./phase0.sh plugin          # one step
#   ./phase0.sh chrome          # stop the kiosk, open bench/ndi-test.html in Chrome
#   ./phase0.sh status | stop | restore
#
# Env overrides: W H FPS FORMAT DEV NDI_NAME BUILD NDI_SDK_TARBALL GST_NDI_SO GST_RS_BRANCH
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
W="${W:-1920}"; H="${H:-1080}"; FPS="${FPS:-60}"; FORMAT="${FORMAT:-UYVY}"; DEV="${DEV:-10}"
NDI_NAME="${NDI_NAME:-HNDI-TEST}"                 # the sender's short name (ndi-testsrc.sh)
# NDI full names are "MACHINE (name)", machine upper-cased. Same-host default; override NDI_FULL= for a remote sender,
# or NDI_URL=ip:port to connect directly without discovery.
NDI_FULL="${NDI_FULL:-$(hostname | tr "[:lower:]" "[:upper:]") ($NDI_NAME)}"
NDI_URL="${NDI_URL:-}"
BUILD="${BUILD:-/root/build}"                 # NOT /data (974M) and NOT /var/tmp (tmpfs)
LOG="${LOG:-/var/tmp/hndi-bench}"; mkdir -p "$LOG" "$BUILD"
NDI_URL="https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz"
export NDI_RUNTIME_DIR_V6=/usr/local/lib
export PATH="$HOME/.cargo/bin:$PATH"

say(){ printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m   ok  %s\033[0m\n' "$*"; }
bad(){ printf '\033[1;31m   FAIL %s\033[0m\n' "$*"; }
gst_minor(){ gst-inspect-1.0 --version 2>/dev/null | awk '/GStreamer/{split($2,a,"."); print a[1]"."a[2]}'; }
plugin_dir(){ pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || echo /usr/lib/x86_64-linux-gnu/gstreamer-1.0; }

deps(){
  say "deps (apt)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-base-apps libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    v4l2loopback-dkms "linux-headers-$(uname -r)" v4l-utils \
    python3-gi gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 \
    git curl build-essential pkg-config libssl-dev avahi-daemon
  ok "GStreamer $(gst_minor), plugin dir $(plugin_dir)"
}

ndi(){
  say "NDI runtime (libndi.so.6 → /usr/local/lib)"
  if ldconfig -p | grep -q libndi.so.6; then ok "already installed: $(ldconfig -p | grep -m1 libndi.so.6)"; return 0; fi
  local tb="${NDI_SDK_TARBALL:-$BUILD/Install_NDI_SDK_v6_Linux.tar.gz}"
  [ -f "$tb" ] || curl -fL --retry 3 -o "$tb" "$NDI_URL" || { bad "download $NDI_URL"; return 1; }
  local d="$BUILD/ndi-sdk"; rm -rf "$d"; mkdir -p "$d"; tar -xzf "$tb" -C "$d"
  local sh; sh=$(find "$d" -maxdepth 2 -name 'Install_NDI_SDK*.sh' | head -1)
  [ -n "$sh" ] && ( cd "$(dirname "$sh")" && echo y | sh "$(basename "$sh")" >"$LOG/ndi-sdk-install.log" 2>&1 )
  local lib; lib=$(find "$d" -path '*x86_64-linux-gnu*' -name 'libndi.so*' -type f | head -1)
  [ -n "$lib" ] || { bad "libndi.so not found under $d"; return 1; }
  install -m 0755 "$lib" /usr/local/lib/ && ( cd /usr/local/lib && ln -sf "$(basename "$lib")" libndi.so.6 && ln -sf libndi.so.6 libndi.so ) && ldconfig
  ok "$(ldconfig -p | grep -m1 libndi.so.6)"
  echo "   NDI SDK license accepted non-interactively — https://ndi.video/sdk/ (never vendored)"
}

plugin(){
  say "gst NDI plugin (libgstndi.so → $(plugin_dir))"
  if gst-inspect-1.0 ndisrc >/dev/null 2>&1; then ok "ndisrc already available"; return 0; fi
  if [ -n "${GST_NDI_SO:-}" ] && [ -f "$GST_NDI_SO" ]; then
    install -m 0644 "$GST_NDI_SO" "$(plugin_dir)/libgstndi.so"
  else
    local minor branch; minor=$(gst_minor)
    case "$minor" in 1.22) branch=0.11 ;; 1.24) branch=0.13 ;; 1.26) branch=0.14 ;; 1.28) branch=0.15 ;; *) branch=main ;; esac
    branch="${GST_RS_BRANCH:-$branch}"
    echo "   GStreamer $minor → gst-plugins-rs branch $branch (override GST_RS_BRANCH=)"
    command -v cargo >/dev/null || { echo "   installing rust (rustup, minimal)"; curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >"$LOG/rustup.log" 2>&1; }
    . "$HOME/.cargo/env" 2>/dev/null || true
    local src="$BUILD/gst-plugins-rs"
    [ -d "$src/.git" ] || git clone --depth 1 -b "$branch" https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git "$src"
    echo "   cargo build -p gst-plugin-ndi --release  (log: $LOG/cargo.log; 10–20 min on an N150)"
    ( cd "$src" && cargo build -p gst-plugin-ndi --release >"$LOG/cargo.log" 2>&1 ) || { bad "cargo build — see $LOG/cargo.log"; return 1; }
    install -m 0644 "$src/target/release/libgstndi.so" "$(plugin_dir)/libgstndi.so"
    cp "$src/target/release/libgstndi.so" "$LOG/libgstndi-gst${minor}-x86_64.so"   # keep a copy for the release asset
  fi
  rm -rf ~/.cache/gstreamer-1.0
  gst-inspect-1.0 ndisrc >/dev/null 2>&1 && ok "ndisrc, ndisink, ndideviceprovider loaded" || { bad "gst-inspect-1.0 ndisrc"; gst-inspect-1.0 ndi 2>&1 | tail -5; return 1; }
}

loopback(){
  say "v4l2loopback → /dev/video$DEV (card_label=NDI, exclusive_caps=1)"
  printf 'options v4l2loopback devices=1 video_nr=%s card_label=NDI exclusive_caps=1 max_buffers=2\n' "$DEV" > /etc/modprobe.d/hndi.conf
  printf 'v4l2loopback\n' > /etc/modules-load.d/hndi.conf
  if lsmod | grep -q '^v4l2loopback'; then [ -e "/dev/video$DEV" ] && { ok "module loaded, /dev/video$DEV present"; return 0; }; modprobe -r v4l2loopback 2>/dev/null; fi
  modprobe v4l2loopback || { bad "modprobe v4l2loopback (dkms status: $(dkms status 2>/dev/null | tr '\n' ' '))"; return 1; }
  sleep 1; [ -e "/dev/video$DEV" ] && ok "$(v4l2-ctl -d /dev/video$DEV --info | grep -E 'Card type|Driver name' | tr -s ' ' | tr '\n' ' ')" || { bad "/dev/video$DEV missing"; return 1; }
}

testsrc(){
  say "software NDI source '$NDI_NAME' ${W}x${H}@${FPS}"
  pgrep -f "ndisink ndi-name=$NDI_NAME" >/dev/null && { ok "already running"; return 0; }
  NAME="$NDI_NAME" W="$W" H="$H" FPS="$FPS" nohup "$HERE/ndi-testsrc.sh" >"$LOG/testsrc.log" 2>&1 &
  sleep 3; pgrep -f "ndisink ndi-name=$NDI_NAME" >/dev/null && ok "pid $(pgrep -f -n "ndisink ndi-name=$NDI_NAME")" || { bad "see $LOG/testsrc.log"; tail -5 "$LOG/testsrc.log"; return 1; }
}

discover(){
  say "NDI discovery (gst-device-monitor, 8 s) — expecting '$NDI_FULL'"
  command -v gst-device-monitor-1.0 >/dev/null || { bad "gst-device-monitor-1.0 missing (gstreamer1.0-plugins-base-apps)"; return 1; }
  local out; out=$(timeout 8 gst-device-monitor-1.0 Source/Network:application/x-ndi 2>&1 | grep -E 'name  *:|url-address' | sed 's/^/   /')
  [ -n "$out" ] && { echo "$out"; ok "$(echo "$out" | grep -c 'name') source(s)"; } || { bad "no NDI source listed (sender running? avahi-browse -rt _ndi._tcp)"; return 1; }
}

receive(){
  local sel; if [ -n "$NDI_URL" ]; then sel="url-address=$NDI_URL"; else sel="ndi-name=$NDI_FULL"; fi
  say "receive '${NDI_URL:-$NDI_FULL}' → /dev/video$DEV as $FORMAT ${W}x${H}"
  pkill -f "gst-launch.*v4l2sink" 2>/dev/null; sleep 0.5
  nohup gst-launch-1.0 -e \
    ndisrc "$sel" receiver-ndi-name="$(hostname) (HNdi bench)" timeout=5000 connect-timeout=10000 max-queue-length=2 \
    ! ndisrcdemux name=d d.video ! queue max-size-buffers=1 leaky=downstream \
    ! videoconvert n-threads=4 ! videoscale \
    ! "video/x-raw,format=$FORMAT,width=$W,height=$H" \
    ! v4l2sink device="/dev/video$DEV" sync=false >"$LOG/receive.log" 2>&1 &
  sleep 6
  if pgrep -f "gst-launch.*v4l2sink" >/dev/null; then
    ok "pipeline pid $(pgrep -f -n "gst-launch.*v4l2sink")"
    v4l2-ctl -d "/dev/video$DEV" --get-fmt-video 2>&1 | grep -E 'Width|Pixel|Frames|VIDIOC' | sed 's/^/   /'
  else bad "see $LOG/receive.log"; tail -8 "$LOG/receive.log"; return 1; fi
}

chrome(){
  say "Chrome bench page (stops kiosk.service; 'phase0.sh restore' brings it back)"
  systemctl stop kiosk 2>/dev/null; sleep 2; pkill -x Xorg 2>/dev/null; sleep 1
  local extra="--auto-accept-camera-and-microphone-capture --remote-debugging-port=9222 ${CHROME_EXTRA:-}"
  setsid nohup kiosk -u "file://$HERE/ndi-test.html" --nocursor --extra "$extra" >"$LOG/kiosk.log" 2>&1 < /dev/null &
  for i in $(seq 1 30); do sleep 1; curl -s http://127.0.0.1:9222/json >/dev/null 2>&1 && break; done
  sleep 6; hud
}

hud(){ curl -s http://127.0.0.1:9222/json 2>/dev/null | python3 -c 'import json,sys; [print("   "+t.get("title","")) for t in json.load(sys.stdin) if t.get("type")=="page"]' 2>/dev/null || echo "   (no devtools on :9222)"; }

shot(){ local f="${1:-$LOG/shot.png}"; DISPLAY=:0 XAUTHORITY=/tmp/.Xauthority import -window root "$f" 2>/dev/null && ok "screenshot $f" || bad "screenshot"; }

cpu(){ say "CPU (top, 3 s)"; top -bn2 -d3 | awk '/^%Cpu|gst-launch|chrome/ && !/grep/' | tail -12 | cut -c1-110; }

status(){
  say "status"
  printf '   gst %s · ndisrc %s · libndi %s · module %s · /dev/video%s %s\n' "$(gst_minor)" \
    "$(gst-inspect-1.0 ndisrc >/dev/null 2>&1 && echo yes || echo NO)" "$(ldconfig -p | grep -q libndi.so.6 && echo yes || echo NO)" \
    "$(lsmod | grep -q '^v4l2loopback' && echo loaded || echo NOT-loaded)" "$DEV" "$([ -e /dev/video$DEV ] && echo present || echo missing)"
  printf '   testsrc %s · receive %s\n' "$(pgrep -f "ndisink ndi-name=$NDI_NAME" >/dev/null && echo running || echo stopped)" "$(pgrep -f "gst-launch.*v4l2sink" >/dev/null && echo running || echo stopped)"
  [ -e "/dev/video$DEV" ] && v4l2-ctl -d "/dev/video$DEV" --get-fmt-video 2>/dev/null | grep -E 'Width|Pixel' | sed 's/^/   /'
  hud
}

stop(){ say "stop bench pipelines"; pkill -f "gst-launch.*v4l2sink" 2>/dev/null; pkill -f "ndisink ndi-name=$NDI_NAME" 2>/dev/null; sleep 1; ok "stopped"; }
restore(){ stop; say "restore kiosk"; pkill -x Xorg 2>/dev/null; sleep 1; systemctl start kiosk && ok "kiosk.service started"; }

run(){ testsrc && discover && receive && status; }
all(){ deps && ndi && plugin && loopback && run; }

case "${1:-all}" in
  all|deps|ndi|plugin|loopback|testsrc|discover|receive|run|chrome|hud|shot|cpu|status|stop|restore) "$1" ;;
  *) echo "usage: $0 [all|deps|ndi|plugin|loopback|testsrc|discover|receive|run|chrome|hud|shot|cpu|status|stop|restore]"; exit 1 ;;
esac
