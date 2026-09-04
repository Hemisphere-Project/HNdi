#!/bin/bash
# HNdi bench — software NDI SOURCE (no Resolume needed). Test pattern with a
# burned-in running time + wall clock, so a photo of the sender next to the
# kiosk output measures end-to-end latency. Uses the same gst NDI plugin
# (ndisink) HNdi builds for the receiver.
#   ./ndi-testsrc.sh                            # 1080p60 UYVY, name "HNDI-TEST"
#   NAME="REGIE" W=1280 H=720 FPS=30 ./ndi-testsrc.sh
set -euo pipefail
NAME="${NAME:-HNDI-TEST}"; W="${W:-1920}"; H="${H:-1080}"; FPS="${FPS:-60}"; PATTERN="${PATTERN:-smpte}"
export NDI_RUNTIME_DIR_V6="${NDI_RUNTIME_DIR_V6:-/usr/local/lib}"
gst-inspect-1.0 ndisink >/dev/null 2>&1 || { echo "ndisink missing — run phase0.sh plugin first"; exit 1; }
echo ".:: HNdi test source :: name='$NAME' ${W}x${H}@${FPS} UYVY"
exec gst-launch-1.0 -e \
  videotestsrc pattern="$PATTERN" is-live=true \
  ! "video/x-raw,format=UYVY,width=$W,height=$H,framerate=$FPS/1" \
  ! timeoverlay halignment=left valignment=top font-desc="Mono 40" \
  ! clockoverlay halignment=right valignment=top time-format="%H:%M:%S" font-desc="Mono 40" \
  ! ndisinkcombiner name=c ! ndisink ndi-name="$NAME" \
  audiotestsrc is-live=true wave=silence ! audioconvert ! c.
