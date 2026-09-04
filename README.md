# HNdi

NDI helpers for Hemisphere boxes (Pi-tools 2026 images). Sibling of
[HKiosk](https://github.com/Hemisphere-Project/HKiosk).

The first node — **input** — makes a box declare itself as an NDI receiver, subscribe to
an NDI source, and expose that video on a local V4L2 device so a browser page can pull it
into a `<video>` with `getUserMedia`. Built for a
[Dropfile](https://github.com/KomplexKapharnaum/Dropfile) station running inside HKiosk on
an Intel N100/N150 mini, but the device is a plain webcam to any page.

```
Resolume ─NDI─▶ hndi-in ─▶ /dev/video10 (v4l2loopback) ─▶ Chrome getUserMedia ─▶ <video>
                  │  persistent output pipeline: intervideosrc → v4l2sink  (device never drops)
                  └  restartable input pipeline: ndisrc → ndisrcdemux → intervideosink
```

The two pipelines are decoupled on purpose: the browser holds the V4L2 device open and its
format must never change, so source loss, source switching and link changes restart only
the **input** side. When no frame arrives for `timeout`, the device keeps ticking and goes
black — it never freezes, and `getUserMedia` never ends.

> **Status:** input node works end to end (verified 2026-09-04 on a Minix Z150 / N150,
> Ubuntu 25.10). See [ROADMAP.md](ROADMAP.md) for the phase plan and [bench/README.md](bench/README.md)
> for the Phase 0 measurements. Producer and WebRTC-relay nodes come later.

## Requirements

- **Ubuntu x86_64** on an Intel mini (N100/N150), bootstrapped with Pi-tools 2026.
- **Secure Boot off** (or a MOK enrolled) — v4l2loopback is a DKMS module. Check with
  `mokutil --sb-state`.
- **avahi-daemon** running — libndi uses it for NDI discovery (Pi-tools images already do).
- A writable root at install time: on a `rorw` box run `rw` first, then reboot when done.

## Install

```bash
git clone https://github.com/Hemisphere-Project/HNdi.git /opt/HNdi
cd /opt/HNdi
rw                 # rorw boxes only — make root writable
sudo ./install.sh
```

`install.sh` installs the GStreamer stack and v4l2loopback from apt, downloads the **NDI
runtime** from NDI (the SDK license is accepted on your behalf; `libndi` is never vendored
here), fetches the **GStreamer NDI plugin** from this repo's releases (or builds it with
cargo if no matching asset exists), configures the loopback device, and links the `hndi`
CLI, the `hndi-in` daemon and its systemd unit. It drops a default `hndi.conf` on the boot
partition and registers `hndi-in` (disabled) in `starter.txt`.

Offline installs: `NDI_SDK_TARBALL=/path/Install_NDI_SDK_v6_Linux.tar.gz` and/or
`GST_NDI_SO=/path/libgstndi.so ./install.sh`.

Enable it:

```bash
systemctl enable --now hndi-in       # or uncomment `hndi-in` in <boot>/starter.txt
reboot                               # rorw boxes: reseal the read-only root
```

## Configure — `<boot>/hndi.conf`

```ini
[input]
source =              # exact NDI name "MACHINE (source)"; blank = first found.
                      #   also: ndi://ip:port or ip:port for a direct connect (no discovery)
width = 1920          # V4L2 device size, stable for the browser. Prefer the LED-native size.
height = 1080
fps =                 # blank = passthrough; e.g. 60 inserts videorate
format = YUY2         # what Chrome accepts from V4L2 (UYVY is NOT enumerated by Chrome)
device = 10           # /dev/video10, card_label=NDI
bandwidth = highest   # highest | lowest (NDI proxy stream) | auto
timeout = 2000        # ms without a frame → black + input restart
receiver_name =       # advertised NDI receiver name; blank = "<hostname> (HNdi)"
api_port = 8791

[discovery]
server =              # NDI Discovery Server IP when mDNS does not cross a WiFi bridge
```

Edit from any laptop by popping the boot partition, like `kiosk.url`. The source picked
live from a control room is persisted separately on `/data`, so it survives a reboot
without touching this file.

## Operate — the `hndi` CLI

```bash
hndi doctor                       # libndi, plugin, module, device, Secure Boot, firewall, API
hndi status                       # state, resolved source, fps, restarts
hndi sources                      # NDI sources seen on the LAN
hndi in source "REGIE (Arena)"    # switch source now      (--persist writes it to /data)
hndi in source --reset            # back to hndi.conf
hndi in bandwidth lowest          # emergency proxy stream over a degrading WiFi bridge
hndi in restart                   # systemctl restart hndi-in
hndi in log                       # journalctl -fu hndi-in
```

## Local API — `http://127.0.0.1:8791`

Loopback only, CORS `*`, no auth. An `https://` page may `fetch` it (localhost is exempt
from mixed-content blocking).

| | |
|---|---|
| `GET /status` | state, resolved source, size/format/fps, `fps_measured`, `frames`, `restarts`, `last_frame_age_ms`, `uptime_s` |
| `GET /sources` | `[{name, url}]` seen on the LAN (cached ≤ 10 s) |
| `PUT /source` | `{"name":"…","persist":false}` — restart the input on a new source |
| `DELETE /source` | drop the override, back to `hndi.conf` |
| `PUT /bandwidth` | `{"mode":"highest\|lowest\|auto"}` |
| `GET /events` | Server-Sent Events: a `status` event on every state change |

## Troubleshooting

- **Chrome sees no camera.** The kiosk must grant capture: HKiosk `--capture` (Phase 2), or
  launch Chrome with `--auto-accept-camera-and-microphone-capture`. Confirm the loopback is
  fed: `hndi status` shows `running`, and `v4l2-ctl -d /dev/video10 --get-fmt-video` shows
  YUY2. A **UYVY** device is invisible to Chrome — keep `format=YUY2`.
- **`hndi doctor` says the plugin is missing.** No release asset matched this box's
  GStreamer minor and cargo isn't present. Re-run `install.sh` (it builds with rust), or
  drop a prebuilt `GST_NDI_SO=…`.
- **No NDI sources found.** `avahi-daemon` must run; sender and receiver share a broadcast
  domain, or set `[discovery] server`. Across a WiFi bridge, prefer unicast (TCP/RUDP),
  never multicast. `hndi sources` and `avahi-browse -rt _ndi._tcp` both list them.
- **`not-negotiated` in the log.** v4l2loopback advertises one colorimetry; the daemon
  probes it and tags the caps. If you changed `device`, make sure it is a v4l2loopback node.

## License

GPL-3.0 — see [LICENSE](LICENSE). The bundled NDI runtime is under the NDI SDK license
(NewTek/Vizrt); the GStreamer NDI plugin is LGPL-2.1. Neither is vendored in this repo.
