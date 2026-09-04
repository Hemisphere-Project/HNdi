# v4l2loopback: dkms package, module options, load at boot. DEV = device number (default 10).
install_v4l2loopback(){
  local dev="${1:-10}"
  say "v4l2loopback → /dev/video$dev (card_label=NDI, exclusive_caps=1)"
  if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warn "Secure Boot is ENABLED — an unsigned DKMS module will not load. Disable it in the BIOS or enroll the MOK."
  fi
  printf 'options v4l2loopback devices=1 video_nr=%s card_label=NDI exclusive_caps=1 max_buffers=2\n' "$dev" > /etc/modprobe.d/hndi.conf
  printf 'v4l2loopback\n' > /etc/modules-load.d/hndi.conf
  if ! modinfo v4l2loopback >/dev/null 2>&1; then
    bad "module not built (dkms status: $(dkms status 2>/dev/null | tr '\n' ' ')) — kernel headers installed?"; return 1
  fi
  if lsmod | grep -q '^v4l2loopback' && [ ! -e "/dev/video$dev" ]; then modprobe -r v4l2loopback 2>/dev/null; fi
  lsmod | grep -q '^v4l2loopback' || modprobe v4l2loopback || { bad "modprobe v4l2loopback"; return 1; }
  sleep 1
  [ -e "/dev/video$dev" ] && ok "$(v4l2-ctl -d /dev/video$dev --info 2>/dev/null | grep -E 'Card type' | tr -s ' ')" || { bad "/dev/video$dev missing"; return 1; }
}
