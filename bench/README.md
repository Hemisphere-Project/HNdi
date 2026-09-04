# Phase 0 bench — record (2026-09-04)

Box: **hmini-001** (Minix Z150, Intel N150 4c, 16 GB, nvme) · Ubuntu 25.10 · kernel 6.17.0-40 ·
GStreamer 1.26.6 · Google Chrome 149 · Secure Boot off · WiFi `wint` 10.2.6.5 · display on HDMI-A-1.
Sender = `bench/ndi-testsrc.sh` on the same box (1080p60 UYVY SMPTE + time overlay), so the
network leg is loopback here; the WiFi / Resolume legs are still to measure on site.

| Check | Result |
|---|---|
| gst NDI plugin build | gst-plugins-rs branch **0.14**, `cargo build -p gst-plugin-ndi` **1 m 32 s** on the N150 (71 crates); loads as ndisrc/ndisink/ndideviceprovider |
| NDI runtime | SDK v6 tarball, unattended; libndi links avahi-client → `avahi-daemon` must run (it does on Pi-tools images) |
| v4l2loopback | **0.15.0** from 25.10 apt, DKMS builds clean on 6.17; `exclusive_caps=1` → device is a capture device only while a writer is attached |
| NDI names | full form `MACHINE (name)`, machine upper-cased: `HMINI-001 (HNDI-TEST)`; discovery via Gst.DeviceMonitor works (properties `ndi-name`, `url-address`); `url-address=ip:port` connects without discovery |
| Chrome accepts | **YUY2 yes** (label `NDI`, 1920×1080@60). **UYVY no** — a UYVY-only loopback is invisible to `enumerateDevices`. I420 not tested (GStreamer side errored, not investigated) |
| Permission | `--auto-accept-camera-and-microphone-capture` → `getUserMedia` OK next to `--deny-permission-prompts`; without it → `NotAllowedError`. Policy file not needed |
| fps in page @1080p60 | **60–61 fps, 0 stalls** (rVFC counter, `bench/ndi-test.html`) |
| CPU (one core = 100 %) | receiver `gst-launch` ~90 % · Chrome ~60 % total (gpu 6 + renderer 4 + capture 2 in `ps`, ~60 in `top`) · sender ~85 % (not present in production). Box total incl. sender ≈ 66 % |
| Latency wired / WiFi | **not yet** — photo method with Resolume on site |
| Sender kill → black → resume | with the bench's single gst-launch: pipeline exits (expected). Real test = `hndi-in` (Phase 1) |

Run: `sudo bench/phase0.sh` (deps → runtime → plugin → loopback → sender → receiver), then
`sudo bench/phase0.sh chrome`; `bench/cdp.py --title` reads the page HUD; `bench/phase0.sh restore`
brings the kiosk back. Logs in `/var/tmp/hndi-bench/`.
