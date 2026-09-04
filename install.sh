#!/bin/bash
#
# HNdi installer — input node. Ubuntu x86_64 (N100/N150 minis bootstrapped with
# Pi-tools 2026). Run as root on a WRITABLE root (golden-image build, or `rw` then
# reboot at the end):   sudo ./install.sh
#
# Env: NDI_SDK_TARBALL=…  GST_NDI_SO=…  (offline installs)   GST_RS_BRANCH=…   DEV=10
#
set -uo pipefail
BASEPATH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$BASEPATH"
. "$BASEPATH/lib/common.sh"; . "$BASEPATH/lib/install-ndi-runtime.sh"; . "$BASEPATH/lib/install-gst-ndi.sh"; . "$BASEPATH/lib/install-v4l2loopback.sh"
need_root
DEV="${DEV:-10}"

say "HNdi install — $(hostname) $(uname -m) $(. /etc/os-release; echo "$PRETTY_NAME") kernel $(uname -r)"
[ "$(uname -m)" = "x86_64" ] || warn "untested architecture $(uname -m)"
root_is_ro && { bad "root filesystem is read-only — run 'rw' first (Pi-tools rorw), then reboot when done"; exit 1; }
command -v apt-get >/dev/null || { bad "needs apt"; exit 1; }
BOOT="$(boot_dir)"; echo "   boot partition: $BOOT"

say "apt dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev v4l2loopback-dkms "linux-headers-$(uname -r)" v4l-utils \
  python3-gi gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 git curl build-essential pkg-config libssl-dev avahi-daemon \
  || { bad "apt"; exit 1; }
ok "GStreamer $(gst_minor)"

install_ndi_runtime || exit 1
install_gst_ndi || exit 1
install_v4l2loopback "$DEV" || exit 1

say "firewall"
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 5353/udp >/dev/null; ufw allow 5960:5990/tcp >/dev/null; ufw allow 5960:5990/udp >/dev/null; ok "ufw: mDNS + NDI 5960–5990 allowed"
else ok "ufw inactive — nothing to open"; fi

say "links, service, config"
chmod +x "$BASEPATH/hndi" "$BASEPATH/input/hndi-in"
ln -sf "$BASEPATH/hndi" /usr/local/bin/hndi
ln -sf "$BASEPATH/input/hndi-in" /usr/local/bin/hndi-in
ln -sf "$BASEPATH/input/hndi-in.service" /etc/systemd/system/hndi-in.service
systemctl daemon-reload
mkdir -p /data/var/hndi/ndi 2>/dev/null || true
[ -f "$BOOT/hndi.conf" ] || cp "$BASEPATH/hndi.conf" "$BOOT/hndi.conf"
if [ -f "$BOOT/starter.txt" ] && ! grep -q '^#\?[[:space:]]*hndi-in[[:space:]]*$' "$BOOT/starter.txt"; then
  printf '\n## [hndi] NDI input node (NDI -> /dev/video%s -> browser)\n# hndi-in\n' "$DEV" >> "$BOOT/starter.txt"
fi
ok "hndi, hndi-in, hndi-in.service linked; $BOOT/hndi.conf in place"

say "HNdi input node INSTALLED"
echo "  - Edit $BOOT/hndi.conf (source, size, device)"
echo "  - Enable at boot:  uncomment 'hndi-in' in $BOOT/starter.txt   (or: systemctl enable --now hndi-in)"
echo "  - Check:           hndi doctor · hndi status · hndi sources"
echo "  - Read-only boxes: reboot now to seal the root filesystem"
