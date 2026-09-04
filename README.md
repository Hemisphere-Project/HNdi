# HNdi

NDI helpers for Hemisphere boxes (Pi-tools 2026 images). Sibling of
[HKiosk](https://github.com/Hemisphere-Project/HKiosk).

**Status: planning — see [ROADMAP.md](ROADMAP.md).** Nothing is installable yet.

## Nodes

| Node | What it does | Status |
|---|---|---|
| **input** (`hndi-in`) | The box advertises itself as an NDI receiver, subscribes to an NDI source and exposes the video on `/dev/video10` (v4l2loopback) so a browser page can `getUserMedia` it into a `<video>`. Local HTTP API on `127.0.0.1:8791` for status and source switching. | planned (Phase 0 bench next) |
| output | Box → NDI sender | later |
| relay | NDI → local WebRTC URL for non-kiosk pages | later |

First target: **Ubuntu Server 24.04 x86_64** on Intel N100/N150 minis, running a
[Dropfile](https://github.com/KomplexKapharnaum/Dropfile) station inside HKiosk.

## Install (once Phase 1 lands)

```
git clone https://github.com/Hemisphere-Project/HNdi.git /opt/HNdi
cd /opt/HNdi && sudo ./install.sh
# edit /boot/hndi.conf, then: systemctl enable --now hndi-in   (or via starter.txt)
```

The installer downloads the NDI runtime from NDI (license accepted on your behalf,
never vendored here) and the GStreamer NDI plugin from this repo's releases.

## License

GPL-3.0 — see [LICENSE](LICENSE).
