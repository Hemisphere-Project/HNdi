# gst NDI plugin (gst-plugins-rs `ndi`): release asset matched by GStreamer minor, else cargo build.
GST_NDI_RELEASES="https://github.com/Hemisphere-Project/HNdi/releases/latest/download"
rs_branch_for(){ case "$1" in 1.22) echo 0.11 ;; 1.24) echo 0.13 ;; 1.26) echo 0.14 ;; 1.28) echo 0.15 ;; *) echo main ;; esac; }
install_gst_ndi(){
  say "gst NDI plugin (libgstndi.so → $(plugin_dir))"
  if gst-inspect-1.0 ndisrc >/dev/null 2>&1; then ok "ndisrc already available"; return 0; fi
  local minor so; minor=$(gst_minor); so="$(plugin_dir)/libgstndi.so"
  if [ -n "${GST_NDI_SO:-}" ] && [ -f "$GST_NDI_SO" ]; then
    install -m 0644 "$GST_NDI_SO" "$so"; echo "   from $GST_NDI_SO"
  elif [ -z "${GST_NDI_NO_DOWNLOAD:-}" ] && curl -fsSL --retry 2 -o "$BUILD/libgstndi.so" "$GST_NDI_RELEASES/libgstndi-gst${minor}-$(uname -m).so" 2>/dev/null; then
    install -m 0644 "$BUILD/libgstndi.so" "$so"; echo "   release asset libgstndi-gst${minor}-$(uname -m).so"
  else
    local branch="${GST_RS_BRANCH:-$(rs_branch_for "$minor")}" src="$BUILD/gst-plugins-rs"
    echo "   no release asset for GStreamer $minor — building gst-plugins-rs branch $branch with cargo (10–20 min)"
    command -v cargo >/dev/null || { curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >"$LOG/rustup.log" 2>&1; }
    . "$HOME/.cargo/env" 2>/dev/null || true
    [ -d "$src/.git" ] || git clone --depth 1 -b "$branch" https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git "$src"
    ( cd "$src" && cargo build -p gst-plugin-ndi --release >"$LOG/cargo.log" 2>&1 ) || { bad "cargo build — see $LOG/cargo.log"; return 1; }
    install -m 0644 "$src/target/release/libgstndi.so" "$so"
    cp "$src/target/release/libgstndi.so" "$LOG/libgstndi-gst${minor}-$(uname -m).so"
    echo "   built; a copy for the release assets is at $LOG/libgstndi-gst${minor}-$(uname -m).so"
  fi
  rm -rf ~/.cache/gstreamer-1.0
  gst-inspect-1.0 ndisrc >/dev/null 2>&1 && ok "ndisrc / ndisink / ndideviceprovider loaded" || { bad "plugin does not load"; gst-inspect-1.0 ndi 2>&1 | tail -3; return 1; }
}
