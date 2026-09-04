# Phase 0 bench — record

Box: hmini-001 (Minix Z150, Intel N150, 16 GB) · Ubuntu 25.10 · kernel 6.17.0-40 ·
GStreamer 1.26.6 · Google Chrome 149 · Secure Boot off · WiFi `wint` 10.2.6.5.

| Check | Result |
|---|---|
| gst NDI plugin build (branch, time) | |
| v4l2loopback (package / upstream) | |
| Chrome accepts UYVY / YUY2 | |
| Permission mechanism (flag / policy) | |
| fps in page @1080p60 | |
| CPU bridge + Chrome | |
| Latency wired / WiFi (photo method) | |
| Sender kill → black → resume | |

Run: `sudo bench/phase0.sh` then `sudo bench/phase0.sh chrome`; `bench/phase0.sh restore`
brings the kiosk back.
