# HNdi shared shell helpers — sourced by install.sh and bench/phase0.sh
say(){ printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m   ok  %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m   warn %s\033[0m\n' "$*"; }
bad(){ printf '\033[1;31m   FAIL %s\033[0m\n' "$*"; }
need_root(){ [ "$(id -u)" -eq 0 ] || { echo "must run as root (sudo)"; exit 1; }; }
boot_dir(){ if [ -d /boot/firmware ]; then echo /boot/firmware; else echo /boot; fi; }
gst_minor(){ gst-inspect-1.0 --version 2>/dev/null | awk '/GStreamer/{split($2,a,"."); print a[1]"."a[2]}'; }
plugin_dir(){ pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || echo "/usr/lib/$(uname -m)-linux-gnu/gstreamer-1.0"; }
root_is_ro(){ grep -q ' / [^ ]* ro[, ]' /proc/mounts; }
: "${BUILD:=/root/build}"; : "${LOG:=/var/tmp/hndi}"
mkdir -p "$BUILD" "$LOG" 2>/dev/null || true
export NDI_RUNTIME_DIR_V6=/usr/local/lib
export PATH="$HOME/.cargo/bin:$PATH"
