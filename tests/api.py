#!/usr/bin/env python3
"""The local HTTP API — the contract every consumer speaks, exercised in process.

`hndi status`, the built-in status page and any player (Dropfile, a control room) read
signal presence from `127.0.0.1:8791`, never from the picture. So the API's shape *is* the
component's interface: a renamed key in `snapshot()` is a crash on a show night, not a
cosmetic change.

This suite starts the real handler against a real (GStreamer-free) node on an ephemeral
port and asserts: every field the CLI and the status page read is present; the mutating
routes validate their input; and a bad route/verb is a clean 404 rather than a traceback.

Run: `python3 tests/api.py` (or `scripts/verify`). Loopback only, no device, no NDI.
"""
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import ROOT, check, eq, load_daemon, report, section  # noqa: E402

m = load_daemon()
TMP = tempfile.mkdtemp(prefix='hndi-api-')

conf = m.load_config(os.path.join(ROOT, 'hndi.conf'))
node = m.Node(conf, TMP, dry_run=True)
node._start_input = lambda src: None
srv = m.serve_api(node, 0)                      # port 0 → the OS picks a free one
BASE = 'http://127.0.0.1:%d' % srv.server_address[1]


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            raw = r.read()
            return r.status, dict(r.headers), (json.loads(raw) if raw and
                                               'json' in r.headers.get('Content-Type', '') else raw)
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, dict(e.headers), (json.loads(raw) if raw else None)


try:
    # ── the status contract ───────────────────────────────────────────────
    section('GET /status — every field its readers index into')
    code, hdr, s = call('GET', '/status')
    eq(code, 200, '/status answers 200')
    eq(hdr.get('Cache-Control'), 'no-store', '/status is never cached (a stale state is a lie)')
    eq(hdr.get('Access-Control-Allow-Origin'), '*', 'a browser page may read it cross-origin')

    # `hndi status` (the CLI) indexes these directly — a missing one is a KeyError on the box.
    cli = ['version', 'state', 'uptime_s', 'restarts', 'source', 'device', 'format', 'width',
           'height', 'fps', 'fps_measured', 'bandwidth', 'mode', 'profile', 'frames',
           'last_frame_age_ms', 'thresholds', 'nosignal', 'receiver', 'config', 'stalled', 'auto']
    missing = [k for k in cli if k not in s]
    eq(missing, [], 'snapshot carries every key `hndi status` and the status page read')
    eq(sorted(s['source']), ['configured', 'override', 'resolved', 'url'], 'source sub-keys')
    eq(sorted(s['thresholds']), ['dead_ms', 'hold_ms', 'stall_ms'], 'threshold sub-keys')
    eq(s['version'], m.VERSION, '/status reports the daemon version')
    eq(s['device'], '/dev/video10', '/status reports the loopback device as a path')
    eq(s['state'], 'stopped', 'a node that was never started reports stopped, not running')
    eq(s['source']['resolved'], '', 'nothing resolved yet')

    section('GET / — the built-in status page')
    code, hdr, body = call('GET', '/')
    eq(code, 200, '/ answers 200')
    check('text/html' in hdr.get('Content-Type', ''), '/ serves html')
    check(b'/status' in body, 'the page polls the same /status this suite just checked')

    section('GET /sources — discovery, empty without a monitor')
    code, _, srcs = call('GET', '/sources')
    eq((code, srcs), (200, []), '/sources answers an empty list rather than failing')

    # ── mutations ─────────────────────────────────────────────────────────
    section('PUT /source — accepted, applied, validated')
    code, _, r = call('PUT', '/source', {'name': 'REGIE', 'persist': False})
    eq(code, 202, 'a source switch is accepted')
    eq(r, {'ok': True, 'name': 'REGIE', 'persist': False}, 'and echoed back')
    eq(node.override, 'REGIE', 'the node took the override (idle_add ran it)')
    eq(call('GET', '/status')[2]['source']['override'], 'REGIE', 'and /status shows it')

    code, _, r = call('PUT', '/source', {'name': 42})
    eq(code, 400, 'a non-string name is refused')
    eq(node.override, 'REGIE', 'and the refused call changed nothing')

    section('PUT /source --persist — survives a restart')
    call('PUT', '/source', {'name': 'KMINI-001 (HNDI-TEST)', 'persist': True})
    check(os.path.isfile(os.path.join(TMP, 'state.json')), 'a persisted override is written to state')
    eq(m.Node(conf, TMP, dry_run=True).override, 'KMINI-001 (HNDI-TEST)',
       'a fresh node reads it back — the box wakes on the source the show left it on')

    section('DELETE /source — back to the configured source')
    eq(call('DELETE', '/source')[0], 202, 'a reset is accepted')
    eq(node.override, '', 'the override is cleared')

    section('PUT /bandwidth — three modes and nothing else')
    for mode in ('lowest', 'highest', 'auto'):
        eq(call('PUT', '/bandwidth', {'mode': mode})[0], 202, f'bandwidth {mode} is accepted')
    eq(node.mode, 'auto', 'the last mode stuck')
    eq(node.auto, True, 'auto is flagged as auto')
    code, _, r = call('PUT', '/bandwidth', {'mode': 'turbo'})
    eq(code, 400, 'an unknown bandwidth mode is refused')
    eq(node.mode, 'auto', 'and the refused call changed nothing')

    section('the edges')
    eq(call('GET', '/nope')[0], 404, 'an unknown GET route is a clean 404')
    eq(call('PUT', '/nope')[0], 404, 'an unknown PUT route is a clean 404')
    eq(call('DELETE', '/nope')[0], 404, 'an unknown DELETE route is a clean 404')
    eq(call('OPTIONS', '/status')[0], 204, 'the CORS preflight answers 204')
finally:
    srv.shutdown()

report('tests/api.py')
