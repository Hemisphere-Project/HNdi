# NDI runtime: libndi.so.6 → /usr/local/lib (downloaded from NDI, license accepted, never vendored)
NDI_URL="https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz"
install_ndi_runtime(){
  say "NDI runtime (libndi.so.6 → /usr/local/lib)"
  if ldconfig -p | grep -q libndi.so.6; then ok "already installed: $(ldconfig -p | grep -m1 libndi.so.6 | sed 's/^ *//')"; return 0; fi
  local tb="${NDI_SDK_TARBALL:-$BUILD/Install_NDI_SDK_v6_Linux.tar.gz}"
  [ -f "$tb" ] || curl -fL --retry 3 -o "$tb" "$NDI_URL" || { bad "download $NDI_URL (offline? pass NDI_SDK_TARBALL=…)"; return 1; }
  local d="$BUILD/ndi-sdk"; rm -rf "$d"; mkdir -p "$d"; tar -xzf "$tb" -C "$d"
  local sh; sh=$(find "$d" -maxdepth 2 -name 'Install_NDI_SDK*.sh' | head -1)
  [ -n "$sh" ] && ( cd "$(dirname "$sh")" && echo y | sh "$(basename "$sh")" >"$LOG/ndi-sdk-install.log" 2>&1 )
  local arch; arch="$(uname -m)-linux-gnu"; [ "$(uname -m)" = "aarch64" ] && arch="aarch64-rpi4-linux-gnueabi"
  local lib; lib=$(find "$d" -path "*$arch*" -name 'libndi.so*' -type f | head -1)
  [ -n "$lib" ] || lib=$(find "$d" -name 'libndi.so.6*' -type f | head -1)
  [ -n "$lib" ] || { bad "libndi.so not found under $d"; return 1; }
  install -m 0755 "$lib" /usr/local/lib/ && ( cd /usr/local/lib && ln -sf "$(basename "$lib")" libndi.so.6 && ln -sf libndi.so.6 libndi.so ) && ldconfig
  ok "$(ldconfig -p | grep -m1 libndi.so.6 | sed 's/^ *//')"
  echo "   NDI SDK license accepted non-interactively on your behalf — https://ndi.video/sdk/"
}
