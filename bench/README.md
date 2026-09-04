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
| device write rate | **60 fps exact** at the v4l2 device (GStreamer fpsdisplaysink around v4l2sink) |
| fps in page @1080p60 | **60 fps** with the bench page fullscreen on the 60 Hz HDMI panel (screenshot). Read over CDP on a non-vsync'd page the rVFC counter free-runs to 300+ — a measurement artifact; the real Dropfile player is vsync-capped, confirm there. Output pipeline uses `v4l2sink sync=true` so the device itself is paced at 60 |
| CPU (one core = 100 %) | receiver `gst-launch` ~90 % · Chrome ~60 % total (gpu 6 + renderer 4 + capture 2 in `ps`, ~60 in `top`) · sender ~85 % (not present in production). Box total incl. sender ≈ 66 % |
| Software-path latency | **~130 ms** (NDI source render → Chrome canvas), 6 samples: 125/127/128/132/133/153 ms, median 130. Measured on-box with a software NDI source: the sender burns its wall-clock (ms-in-minute) into each frame as 7-seg digits, the page draws its own clock in the same render pass, one screenshot holds both → gap = latency. Covers NDI SDK buffering (loopback, ~0 network) + ndisrc + convert/scale + intervideo + v4l2loopback + Chrome capture + rVFC draw. Does NOT include the monitor's own display latency (~1–2 frames) or real NDI network transit (Resolume over Ethernet/WiFi) — those are the remaining on-site legs |
| Sender kill → black → resume | **`hndi-in` verified**: kill sender → `running → retrying → resolving`, device keeps emitting the last frame then black (getUserMedia never ends); sender back → `running`, `restarts` increments; `PUT /source` (name or `ndi://ip:port`) switches in ~3 s; `DELETE /source` reverts to `hndi.conf`; all with the browser device held open |
| intervideosrc → v4l2sink | needs a `capssetter join=true` adding interlace-mode=progressive, pixel-aspect-ratio=1/1, multiview-mode=mono and the device's own colorimetry (v4l2loopback advertises one; the daemon probes it) — else `not-negotiated` |

Run: `sudo bench/phase0.sh` (deps → runtime → plugin → loopback → sender → receiver), then
`sudo bench/phase0.sh chrome`; `bench/cdp.py --title` reads the page HUD; `bench/phase0.sh restore`
brings the kiosk back. Logs in `/var/tmp/hndi-bench/`.
