# HNdi — roadmap

**HNdi** is the NDI toolset for Hemisphere boxes. First node: **input** — the box
declares itself as an NDI receiver, subscribes to an NDI source and exposes the
video as a local V4L2 device that a browser page opens with `getUserMedia` and
draws into a `<video>` / canvas / WebGL. First consumer: a Dropfile station running
inside HKiosk on an N150 mini (Ubuntu 25.10, Pi-tools 2026 image).

```
Resolume → NDI (LAN / WiFi bridge) → hndi-in (GStreamer) → /dev/video10 (v4l2loopback)
        → Chrome getUserMedia → <video> → Dropfile player canvas
```

Repos touched: **HNdi** (this repo, box side), **HKiosk** (Chrome capture
permission), **Dropfile** (server model + player + control room).

Origin: a first roadmap written with claude.chat (2026-09-03), reviewed against the
three repos and the hub on 2026-09-04; the decisions below supersede it.

---

## Status (2026-09-04)

- **Phase 0 — bench: PASSED** on hmini-001 (Minix Z150 / N150, Ubuntu 25.10). Live NDI in
  Chrome via `getUserMedia` at a paced **60 fps**, format **YUY2**, permission via
  `--auto-accept-camera-and-microphone-capture`. Numbers in [bench/README.md](bench/README.md).
- **Phase 1 — input node: WORKING.** `hndi-in` daemon (two pipelines, state machine, HTTP
  API, SSE), `hndi` CLI + `doctor`, config, installer + lib, CI workflow — all landed and
  verified on the box (source resolve/connect/run, black-on-loss + auto-recover, `PUT/DELETE
  /source`). Left to close the phase: tag a release so CI publishes the plugin asset, then a
  field pass. The gst NDI plugin currently builds on the box with cargo (~1m30s).
- **Phases 2–6** — not started (HKiosk `--capture`, then Dropfile model + player).

Remaining Phase 0 field items (need Resolume/OBS on the KXKM LAN + the display): end-to-end
**latency** by the photo method, and the **WiFi-bridge** degradation behaviour.

## Decisions locked (2026-09-04)

1. **Transport into the browser = v4l2loopback + `getUserMedia`** — raw UYVY frames,
   no encode, `video.srcObject`. A local WebRTC/WHEP "URL" sink is a later optional
   node (`relay/`), not v1.
2. **Bridge = a Python 3 + PyGObject daemon from day one**, with two decoupled
   GStreamer pipelines (persistent output, restartable input), a local HTTP API and a
   CLI. No bash-loop MVP.
3. **gst NDI plugin shipped as a GitHub release asset** built by CI on `ubuntu-24.04`,
   matched by GStreamer minor; a cargo build on the box is the fallback only.
4. **Dropfile: NDI source per *station***, scenes only toggle `ndi.on`. Newest live
   source wins (a phone going live overlays NDI and reverts). A scene with NDI on keeps
   its playlist as fallback while no frames arrive.
5. **Audio out of scope for v1.** The design keeps the door open (interaudio branch →
   audiohub's `snd-aloop`).
6. **FullHD is the ceiling**; LED-native sizes are the normal case. The bench must still
   pass at 1080p60.
7. **Wireless is a first-class failure mode**: the link degrades or drops; the wall must
   go black (never freeze) and recover by itself.
8. Repo public, **GPL-3** (like HKiosk). Names: `hndi-in.service`, `hndi` CLI,
   `/boot/hndi.conf`, `/data/var/hndi/`. API on `127.0.0.1:8791`.

## Target platform facts (verified 2026-09-04 on hmini-001)

- **hmini-001 = Minix Z150 (Intel N150, 16 GB, nvme)** at `10.2.6.5` on the KXKM LAN, a
  production box lent as the bench. It runs **Ubuntu 25.10, kernel 6.17.0-40, GStreamer
  1.26.6, Google Chrome 149**, Pi-tools `af53763`, Secure Boot disabled, 20 G root +
  a **974 M `/data`** (too small for build trees — build under `/root/build`), on WiFi
  (`wint`, eth0 unplugged), ufw inactive. The show fleet (IMA-Niort, 24/09/2026) is
  4 Minix Z150 + 3 Beelink N150 cloned from the `hmini-000` golden image, so this is the
  reference platform — **not** the 24.04 / GStreamer 1.24 base the hub's N100 notes
  describe.
- Read-only root (Pi-tools `rorw`), `/data` rw. Runtime remount-ro is unreliable on these
  minis → never rely on writing `/boot` or `/etc` at runtime; a reboot seals. Bench work:
  `rw` first, reboot at the end.
- Ubuntu ships **no `gstreamer1.0-plugins-rs`**. `gst-plugin-ndi` (gst-plugins-rs, branch
  0.14 for GStreamer 1.26) loads `libndi` at runtime (`NDI_RUNTIME_DIR_V6`), supports SDK 5
  and 6, exposes `ndi-name`, `url-address`, `receiver-ndi-name`, `bandwidth`,
  `color-format` (`uyvy-bgra` default), `timeout` (5000), `connect-timeout` (10000),
  `max-queue-length` (10), `timestamp-mode`; `ndisrcdemux` (rank primary) splits
  `video` / `audio`; `ndideviceprovider` lists sources. GitHub has no 25.10 hosted runner:
  CI builds inside an `ubuntu:25.10` container on an `ubuntu-24.04` runner.
- **NDI SDK v6 Linux** tarball downloads unattended:
  `https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz`
  (61 MB, refreshed 2026-04). The installer accepts the license; `libndi` is never
  vendored in the repo.
- **v4l2loopback-dkms 0.15.0** in 25.10 builds cleanly against 6.17 (bench 2026-09-04).
  Any DKMS module needs Secure Boot off or a MOK enrolled: `mokutil --sb-state`.
- Chrome (HKiosk x86 = Google Chrome `.deb`) does **not** list UYVY among its usable
  V4L2 formats (bench 2026-09-04: a UYVY-only loopback is invisible to
  `enumerateDevices`). **YUY2 works**: label `NDI`, 1920×1080@60, 60 fps in the page,
  0 stalls. So the bridge converts NDI's UYVY to YUY2 (a byte swap in `videoconvert`).
  `--auto-accept-camera-and-microphone-capture` grants `getUserMedia` with no prompt even
  next to HKiosk's `--deny-permission-prompts` (bench 2026-09-04) — the enterprise policy
  is the fallback, not the default. Loopback (`127.0.0.1`, `localhost`) is exempt from
  mixed-content blocking, so an https page may `fetch` the local API.
- **NDI is pull-based**: a receiver subscribes to a source; it only *advertises* its
  own name (`receiver-ndi-name`). Operator-side routing ("choose what a box shows from
  the Resolume side") = NDI Router (NDI Tools), one virtual source per box; the box
  subscribes to that stable name.

---

## Architecture

### Daemon `hndi-in`

Python 3, PyGObject (`Gst` 1.0), stdlib `http.server`; runs as root under systemd.

**Output pipeline** — persistent, never restarted while the daemon lives:

```
intervideosrc channel=ndi timeout=<timeout ns>
  ! video/x-raw,format=YUY2,width=W,height=H,framerate=F/1
  ! v4l2sink device=/dev/video10 sync=false
```

**Input pipeline** — restartable:

```
ndisrc ndi-name="<source>" receiver-ndi-name="<host> (HNdi)" bandwidth=<mode>
       color-format=uyvy-bgra timeout=<ms> connect-timeout=<ms> max-queue-length=2
  ! ndisrcdemux name=d
  d.video ! queue max-size-buffers=1 leaky=downstream
          ! videoconvert n-threads=4 ! videoscale
          ! video/x-raw,format=YUY2,width=W,height=H
          ! intervideosink channel=ndi
```

`videorate` only when `fps` is pinned. `videoscale` is pass-through when the sender already delivers W×H (LED-native comp);
`videoconvert` does the UYVY→YUY2 byte swap Chrome needs.

**Why two pipelines.** Chrome holds `/dev/video10` open and its caps must never
change. Source loss, WiFi drops, source switching and bandwidth changes restart only
the input side. `intervideosrc` repeats the last frame for `timeout`, then outputs
black → no frozen frame on the wall, and the device keeps ticking so `getUserMedia`
never ends. Audio (later) is the same pattern with `interaudiosink`/`interaudiosrc`.

**State machine.** `stopped → resolving → connecting → running → retrying → resolving…`
- *resolving*: `Gst.DeviceMonitor` (`Source/Network:application/x-ndi`) every 3 s until
  the wanted source (or, with a blank source, the first one) appears.
- *running → retrying*: no frame for `timeout`, or the pipeline errors/EOS.
- Every transition is journaled and exposed on the API; counters: `restarts`, `frames`,
  `fps_measured` (pad probe on `intervideosink`), `last_frame_age_ms`.

**Source resolution order.** `/data/var/hndi/state.json` override (set by the API with
`persist:true`) → `[input] source` in `/boot/hndi.conf` → first source seen.

### Local API (`127.0.0.1:8791`, CORS `*`, loopback only, no auth)

| Method | Path | Body / result |
|---|---|---|
| GET | `/status` | `{ node:"input", state, source:{configured, override, resolved, url}, receiver, width, height, fps, fps_measured, format, device, bandwidth, frames, restarts, last_frame_age_ms, uptime_s, version }` |
| GET | `/sources` | `[ {name, url} ]` from the device monitor (cache ≤ 10 s) |
| PUT | `/source` | `{ "name": "…", "persist": false }` → restarts the input pipeline; `persist:true` also writes the override to `state.json` |
| DELETE | `/source` | drop the override, back to `hndi.conf` |
| PUT | `/bandwidth` | `{ "mode": "highest" \| "lowest" \| "auto" }` |
| GET | `/events` | Server-Sent Events: a `status` event on every state change + heartbeat every 5 s (optional; polling `/status` at 1 Hz is fine) |

### CLI `hndi`

```
hndi status [--json]            hndi sources
hndi in source "<name>" [--persist]   hndi in source --reset
hndi in bandwidth highest|lowest|auto hndi in restart     hndi in log
hndi doctor    # libndi present, plugin loads, module loaded, device caps, Secure Boot, firewall
```

### Config `/boot/hndi.conf` (INI; copied at install, never clobbered)

```ini
[input]
source =              # exact NDI name, e.g. "REGIE (Resolume Arena - Output)"; blank = first found
width = 1920          # loopback caps (stable for Chrome). Prefer the LED-native size.
height = 1080
fps =                 # blank = passthrough; e.g. 60 inserts videorate
format = YUY2         # what Chrome accepts from V4L2 (UYVY is not listed by Chrome)
device = 10           # /dev/video10, card_label=NDI
bandwidth = highest   # highest | lowest (NDI proxy stream) | auto (phase 6)
timeout = 2000        # ms without a frame before black + input restart
receiver_name =       # advertised NDI receiver name; blank = "<hostname> (HNdi)"
nosignal = black      # black | slate (hostname + source burned in, for bare test pages)
api_port = 8791

[discovery]
server =              # NDI Discovery Server IP when mDNS does not cross a bridge
```

Runtime state on `/data`: `/data/var/hndi/state.json` (source override),
`/data/var/hndi/ndi/ndi-config.v1.json` (`NDI_CONFIG_DIR`, discovery server).

### Repo layout

```
HNdi/
  README.md  ROADMAP.md  LICENSE (GPL-3)
  module.ini                 # Pi-tools 2026 manifest (group=hndi, platforms=x86, script=yes)
  install.sh                 # platform check, deps, runtime, plugin, loopback, service, boot config, starter entry
  hndi                       # CLI (python3)
  hndi.conf                  # default config → /boot/hndi.conf
  lib/
    common.sh                # boot dir / platform / rorw helpers
    install-ndi-runtime.sh   # SDK download (or NDI_SDK_TARBALL=…), license, libndi.so.6 → /usr/local/lib
    install-gst-ndi.sh       # release asset by GStreamer minor → gstreamer-1.0/ plugin dir; cargo fallback
    install-v4l2loopback.sh  # dkms package, upstream fallback, modules-load/modprobe config, Secure Boot check
  input/
    hndi-in                  # the daemon (python3, single file)
    hndi-in.service
    nosignal.png
  bench/
    phase0.sh                # the bench as a script (deps → runtime → plugin → loopback → test pipeline)
    ndi-test.html            # getUserMedia → <video> → canvas, fps + stall counter
    README.md                # measured results — the Phase 0 gate record
  .github/workflows/
    gst-ndi.yml              # build libgstndi.so on ubuntu-24.04, attach to the release
```

Future nodes sit beside `input/`: `output/` (producer: X11 / HPlayer capture →
`ndisink`), `relay/` (NDI → local WebRTC/WHEP for non-kiosk pages), other platforms
(the SDK ships aarch64 libs; the plugin builds on arm64 runners).

### systemd `hndi-in.service`

`After=network-online.target` · `ExecStartPre=/sbin/modprobe v4l2loopback` ·
`Environment=NDI_CONFIG_DIR=/data/var/hndi/ndi` · `Restart=always` · `RestartSec=5` ·
`StartLimitIntervalSec=0` · `Nice=-5` · `KillMode=mixed`. Independent of
`kiosk.service` (either restarts alone). Registered **disabled** in `starter.txt` as
`hndi-in` (Pi-tools convention).

### `install.sh`

1. root + `x86_64` + apt check; boot dir (`/boot/firmware` else `/boot`); warn when
   root is read-only (run on the golden-image build, or inside `rw … reboot`).
2. apt: `gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good
   gstreamer1.0-plugins-bad python3-gi gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0
   v4l2loopback-dkms linux-headers-$(uname -r) v4l-utils avahi-daemon`.
3. NDI runtime, gst plugin, v4l2loopback (`/etc/modules-load.d/hndi.conf`,
   `/etc/modprobe.d/hndi.conf`: `options v4l2loopback devices=1 video_nr=10
   card_label=NDI exclusive_caps=1 max_buffers=2`); self-checks `gst-inspect-1.0 ndisrc`
   and `v4l2-ctl -d /dev/video10 --all`.
4. ufw, if active: `5353/udp`, `5960:5990/tcp`, `5960:5990/udp` (RUDP).
5. Links: `hndi` → `/usr/local/bin`, unit → `/etc/systemd/system`, `hndi.conf` → boot
   (no clobber), `/data/var/hndi/` dirs, starter entry.

Idempotent. Offline: `NDI_SDK_TARBALL=… GST_NDI_SO=… ./install.sh`.

### CI `gst-ndi.yml`

Runner `ubuntu-24.04` running the build inside an **`ubuntu:25.10` container** (GStreamer
1.26 = the fleet): apt gst dev packages, rustup stable, clone gst-plugins-rs at the branch
matching 1.26 (0.14), `cargo build -p gst-plugin-ndi --release`, upload
`libgstndi-gst1.26-x86_64.so` + `SHA256SUMS` and attach them to the tag's release.
`workflow_dispatch` input for another Ubuntu/gst pair when the fleet moves. LGPL asset; license text
alongside.

---

## Phases

### Phase 0 — Bench on a real N150 (gate · ~½ day · field)

Runs on hmini-001 (rw, display attached). No external sender needed for the software
pass: `bench/ndi-testsrc.sh` emits a test NDI stream from the same plugin; Resolume/OBS on
the KXKM LAN come in for the network and latency legs. `bench/phase0.sh` runs the steps;
results go to `bench/README.md`.

1. deps + NDI runtime + plugin (cargo on the box the first time; CI asset afterwards) +
   loopback module.
2. `gst-device-monitor-1.0 Source/Network:application/x-ndi` lists the sender;
   `hndi doctor` green.
3. Pipeline at UYVY 1920×1080 (then YUY2) → `v4l2-ctl -d /dev/video10 --all` shows it.
4. `bench/ndi-test.html` in HKiosk (`kiosk -u file:///opt/HNdi/bench/ndi-test.html`),
   first with `--extra "--auto-accept-camera-and-microphone-capture"`, then with the
   policy file if the flag does not take.
5. Measure: in-page fps (rVFC counter) ≥ 58 at 1080p60; CPU (bridge + Chrome) < 70 %
   on `top`; end-to-end latency by the running-counter photo method, wired and, if
   available, over the WiFi bridge; kill the sender → black within `timeout`, back
   < 5 s when it returns; `getUserMedia` never ends across input restarts.
6. `fetch("http://127.0.0.1:8791/status")` from an https page is not blocked.

**Gate outputs:** `format` default (UYVY/YUY2), permission mechanism (flag/policy),
fps / CPU / latency numbers, v4l2loopback package vs upstream.

### Phase 1 — HNdi input node v1 (~2–3 days · code)

Everything under *Architecture*: daemon (two pipelines, state machine, API, SSE), CLI,
config, installer, service, CI workflow + first release with the plugin asset, README
(install, config, API, troubleshooting), `hndi doctor`.

**Acceptance on the box:** cold boot → `/dev/video10` with the configured caps < 15 s
after network-online; `hndi status` correct; sender killed/restarted → black then
resume, no process leak, `restarts` increments; `PUT /source` switches in ~3 s without
disturbing an open `getUserMedia`; daemon restart → the Chrome track ends and a page
re-acquires; `journalctl -u hndi-in` readable; `install.sh` re-runnable.

### Phase 2 — HKiosk: media capture for the kiosk origin (~½ day · code)

Generic, not NDI-specific. New `--capture` option in `kiosk.url` → `KIOSK_CAPTURE=1`.
In `openbox-chromium`: add `--auto-accept-camera-and-microphone-capture` when set (if
the bench proved it) and/or write the Chrome policy
`{ VideoCaptureAllowed, VideoCaptureAllowedUrls: [<origin>, "http://localhost",
"file://*"], AudioCapture… }` to a **tmpfs** dir `/run/hkiosk/policies/`, with
`/etc/opt/chrome/policies/managed` and `/etc/chromium/policies/managed` symlinked to it
at install time (root is read-only at runtime). Origin derived from the URL after the
loader `#`. If the URL is plain `http://` and not localhost, add
`--unsafely-treat-insecure-origin-as-secure=<origin>`. README section "Camera / NDI
input" → HNdi.

**Acceptance:** `getUserMedia({video:true})` resolves with no prompt from the kiosk
origin; `chrome://policy` shows the entries (policy path).

### Phase 3 — Dropfile server: model, API, admin (~1 day · code)

- `lib/defaults.js`: `defaultMediaFilter()` / `cleanMediaFilter()` gain `ndi` (missing →
  `true`); `defaultSceneNdi() → { on:false }` / `cleanSceneNdi`; `defaultStationNdi() →
  { source:'' }` / `cleanStationNdi` (trim, ≤ 128 chars).
- `routes/admin.js`: `makeScene` + `serializeScene` carry `ndi:{on}`; scene `PUT`
  accepts `ndi.on` → `refreshSceneMachines`; station `PUT` accepts `ndi.source` →
  `cleanStationNdi`, save, `broadcastActive` for that machine.
- `lib/migrate.js#upgradeStore`: scenes gain `ndi`, stations gain `ndi`; idempotent.
- `lib/playlist.js#activeInfo`: `ndi: { on: !!(a.source.ndi && a.source.ndi.on) &&
  show.ndi, source: (a.station && a.station.ndi && a.station.ndi.source) || '' }`.
- Drop-page payloads (`routes/drop.js`, `drop-meta`) never carry `ndi` (unit test).
- Admin: scene card chip **NDI** (on/off, not part of `acceptAll`); station settings
  modal: "NDI source" text input (blank = box default); station media-filter popover
  gets the `ndi` chip; `statusLabel`: `mode === 'ndi'` → `● NDI`, `ndiError` →
  `⚠ NDI: …`.

**Acceptance:** `GET /api/player/:token` → `active.ndi = { on, source }`; station
filter `ndi=false` → `on:false`; a legacy `db.json` upgrades on boot.

### Phase 4 — Dropfile player: `www/ndi.js` (~1 day · code + field)

`class NdiInput` with the `StreamReceiver` contract: `start(source)`, `stop()`,
`has()`, `list()` → `[{ id:'ndi', name:'NDI', video, joinedAt }]`, `error`.
Acquire loop: `enumerateDevices` (throwaway `getUserMedia` first if labels are empty)
→ `videoinput` labelled `NDI` → `getUserMedia({ video: { deviceId:{exact},
width:{ideal}, height:{ideal}, frameRate:{ideal:60} }, audio:false })` → hidden muted
`<video autoplay playsinline>`; retry every 2 s; `track.onended` → retry. **Signal
presence comes from the bridge**: poll `GET /status` at 1 Hz (or `/events`); `has()` is
true only when the track is live **and** bridge `state === 'running'` — black-from-
timeout never counts as live, so the playlist fallback kicks in. If `source` is
non-empty and differs from the bridge's resolved source → `PUT /source` (no persist).
Never throws.

`player.js`: `ndi = new NdiInput({ onChange: onStreamChange })`;
`updateStreamMembership()` also does `active.ndi.on ? ndi.start(active.ndi.source) :
ndi.stop()`; `liveList() = [...ndi.list(), ...receiver.list()]` sorted by `joinedAt`,
used by `onStreamChange`, `drawStreams`, `updateAudio`, `updateCounter` (newest wins;
grid mode tiles NDI like any stream); `emitStatus`: `mode:'ndi'` when the active live
source is NDI, `ndiError` when `active.ndi.on && !ndi.has()`, `ndi: { state, source }`
from the bridge throttled to changes. Optional: drive `drawStreams` from
`requestVideoFrameCallback` on the NDI video (measured in Phase 0).

**Acceptance on the N150:** activate an NDI scene → picture < 1 s; another scene →
playlist; sender stops → playlist within `timeout` + 1 s, back when it returns, no
reload; phone *Go live* overlays and reverts; admin shows `● NDI`.

### Phase 5 — Source selection from the control room (~½ day · code)

The station "NDI source" input becomes a `<datalist>` fed by the union of
`status[*].ndi.sources` reported by online machines (bridge `/sources` relayed in
`player-status`, throttled to 10 s); free text still allowed. The station column shows
the bridge's resolved source under the status line and a warning when `restarts`
climbs. Persisting to the box (`persist:true`) is an explicit "Save as box default"
action, not the default.

**Acceptance:** picking a source switches the box in ~3 s with no reload; the list
shows the Resolume outputs seen on the LAN.

### Phase 6 — Hardening and options (as needed · code + field)

- **WiFi degradation** (`bandwidth = auto`): the daemon scores the link from
  `fps_measured` and the stall count over a sliding 10 s window; ≥ 3 stalls or fps
  < 50 % of expected → restart the input at `bandwidth=lowest` (NDI proxy stream) with
  a 60 s cool-down; back to `highest` after 60 s clean. Sender-side notes in the README:
  unicast TCP / RUDP, never multicast, over wireless; NDI Discovery Server across
  bridged subnets (`[discovery] server`).
- **Audio:** `d.audio ! audioconvert ! interaudiosink` + persistent `interaudiosrc !
  alsasink` into audiohub's `snd-aloop`; Dropfile treats it like a stream's audio.
- **Watchdog:** `restarts` and `last_frame_age_ms` surfaced in Dropfile status with
  thresholds.
- **Docs:** cross-links HKiosk ↔ HNdi ↔ Dropfile; Dropfile `ROADMAP.md` gains a
  "Phase 6 — NDI input" entry in its own style.

### Later

Producer node `output/` (X11 / HPlayer → `ndisink`) for boxes that must *send*;
`relay/` WebRTC-WHEP sink for non-kiosk pages and remote monitoring; aarch64 (RPi 4/5);
multi-source (two loopback devices, PiP); an NDI Router recipe per box.

---

## Conventions

- Pi-tools module contract: `module.ini` + `install.sh`, symlinks into `/usr/local/bin`
  and `/etc/systemd/system`, config on the boot partition, state on `/data`, disabled
  `starter.txt` entry; Pi-tools 2026 systemd hygiene (`StartLimitIntervalSec=0`,
  `RestartSec=5`).
- Daemon: Python 3 stdlib + PyGObject only (no pip on a read-only image); one file;
  `--config`, `--dry-run`, `--verbose`.
- Never vendor `libndi`; the installer downloads it and accepts the NDI license on the
  operator's behalf (and prints the license URL).
- Dropfile: CommonJS, no build step; every mutation through a `cleanX()`; keep the
  `settings` wire shape; add to `active`, never rename `stream*` events.
- One commit per phase per repo: `ndi: phase N — …` in Dropfile and HKiosk. Hardware
  acceptance at the end of each phase on the real N150.

## Open items

- **Timeline** — first show is **IMA-Niort (KXKM), 24/09/2026**. Phases 0–4 must land
  before; 5–6 as time allows. The minis may finally be driven from RPi-Regie/HPlayer2
  rather than Dropfile as-is — parked until NDI injection works.
- **Bench hardware** — hmini-001 (10.2.6.5, via rachael) since 2026-09-04; Resolume/OBS
  on the KXKM LAN for the latency and WiFi legs when Thomas is on site.
- **Hub** — create the `hndi` project in 37Projects (component, `uses: [pi-tools,
  hkiosk]`, consumer `dropfile`); Phase 0 is its first task.
- **Sender-side recipe** — Resolume comp at LED-native size, fixed NDI output name,
  unicast (TCP/RUDP) for wireless; written after Phase 0 with real numbers.
