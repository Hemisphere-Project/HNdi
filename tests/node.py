#!/usr/bin/env python3
"""The input node's logic — everything that decides *what* to build, without building it.

Four groups, each guarding a rule the daemon exists to enforce (ROADMAP.md, and the two
knowledge notes the hub keeps on this component):

  1. source matching   — NDI advertises `MACHINE (source)`; an operator writes what they know
  2. config            — /boot/hndi.conf is edited by hand on a show day, comments and all
  3. pipeline descriptions — the intervideo seam only passes frames if both halves agree
  4. bandwidth=auto    — degrade to the proxy stream on sustained trouble, not on a blip

Run: `python3 tests/node.py` (or `scripts/verify`). No GStreamer, no device, no network.
"""
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import ROOT, check, contains, eq, load_daemon, report, section  # noqa: E402

m = load_daemon()
TMP = tempfile.mkdtemp(prefix='hndi-test-')


def conf_from(text):
    p = os.path.join(TMP, 'c%d.conf' % abs(hash(text)))
    with open(p, 'w') as f:
        f.write(text)
    return m.load_config(p)


def node_from(conf):
    n = m.Node(conf, TMP, dry_run=True)
    n._start_input = lambda src: None      # would need GStreamer; the policy is what we test
    return n


# ── 1. source matching ────────────────────────────────────────────────────
# kmini-001, 2026-09-04: a cue naming "HNDI-TEST" dropped a running
# "KMINI-001 (HNDI-TEST)" feed and searched forever, because only the exact name matched.
#
# The three tiers overlap, so each case below is chosen to give a DIFFERENT answer if its
# tier is removed — a fixture that any one tier can satisfy alone proves nothing.
section('source matching — full name, "(name)" suffix, then fragment')
S = [{'name': 'KMINI-001 (HNDI-TEST)', 'url': ''},
     {'name': 'REGIE (Resolume Arena - Output)', 'url': ''},
     {'name': 'HNDI-TEST', 'url': ''}]
match = m.Node._match

eq(match('KMINI-001 (HNDI-TEST)', S), S[0], 'the full advertised name matches')
eq(match('HNDI-TEST', S), S[2], 'an exact name beats a "(name)" suffix elsewhere')
# Drop the suffix tier and the fragment tier answers CASA first — the wrong box, silently.
SUF = [{'name': 'CASA (REGIE-BACKUP)', 'url': ''}, {'name': 'KMINI-001 (REGIE)', 'url': ''}]
eq(match('REGIE', SUF), SUF[1], 'the "(name)" suffix beats a mere fragment of another source')
eq(match('resolume arena', S), S[1], 'a case-insensitive fragment matches last')
eq(match('NOT-ON-THIS-LAN', S), None, 'an absent source resolves to nothing')
eq(match('KMINI', S), S[0], 'a fragment of the machine half matches too')

# ── 2. config ─────────────────────────────────────────────────────────────
section('config — the file a human edits on a show day')
shipped = m.load_config(os.path.join(ROOT, 'hndi.conf'))
eq(shipped['device'], 10, 'shipped hndi.conf: device 10 parses past its inline comment')
eq(shipped['format'], 'YUY2', 'shipped hndi.conf: YUY2 (the format Chrome lists)')
eq(shipped['width'], 1920, 'shipped hndi.conf: width 1920')
eq(shipped['fps'], 0, 'shipped hndi.conf: blank fps means passthrough, not 0 fps caps')
eq(shipped['bandwidth'], 'highest', 'shipped hndi.conf: bandwidth highest')
eq(shipped['profile'], 'lowlatency', 'shipped hndi.conf: profile lowlatency (the golden image)')
eq((shipped['stall_ms'], shipped['dead_ms'], shipped['hold_ms']), (800, 8000, 1500),
   'shipped hndi.conf: the three recovery thresholds')
check(shipped['receiver_name'].endswith('(HNdi)'), 'a blank receiver_name becomes "<host> (HNdi)"')

# Every key the shipped file sets must be a key the daemon knows: a typo in /boot/hndi.conf
# is silent otherwise — the daemon reads its default and the show runs on the wrong setting.
known = {k for sec in m.DEFAULTS.values() for k in sec}
import configparser  # noqa: E402
raw = configparser.ConfigParser(inline_comment_prefixes=('#', ';'))
raw.read(os.path.join(ROOT, 'hndi.conf'))
unknown = sorted(k for s in raw.sections() for k in raw[s] if k not in known)
eq(unknown, [], 'shipped hndi.conf sets no key the daemon does not read')
eq(sorted(raw.sections()), ['discovery', 'input'], 'shipped hndi.conf has the sections the daemon reads')

robust = conf_from('[input]\nprofile = robust\n')
eq(robust['jitter_ms'], 100, 'profile robust: a 100 ms receive jitter buffer (WiFi)')
eq(robust['ndi_queue'], 8, 'profile robust: a deeper ndisrc queue')
low = conf_from('[input]\nprofile = lowlatency\n')
eq((low['jitter_ms'], low['ndi_queue']), (0, 2), 'profile lowlatency: hold nothing back')

junk = conf_from('[input]\nbandwidth = turbo\nprofile = yolo\n')
eq(junk['bandwidth'], 'highest', 'an unknown bandwidth falls back to highest')
eq(junk['profile'], 'lowlatency', 'an unknown profile falls back to lowlatency')
eq(conf_from('[input]\ntimeout = 2500\n')['hold_ms'], 2500, 'the legacy `timeout` key still sets hold_ms')
eq(conf_from('[input]\nsource = REGIE   ; on air\n')['source'], 'REGIE',
   'a `;` comment is stripped from a value, not parsed into it')

# ── 3. pipeline descriptions ──────────────────────────────────────────────
# The output half is never torn down, so Chrome's caps never change; the input half is
# restartable. Frames only cross the intervideosink/intervideosrc seam untouched if both
# halves carry the same channel and the same caps shim.
section('pipeline descriptions — the intervideo seam')
n = node_from(shipped)
eq(n.probe_colorimetry(), 'sRGB', 'colorimetry falls back to sRGB when v4l2sink cannot be probed')
out, inp = n.out_desc(), n.in_desc({'name': 'KMINI-001 (HNDI-TEST)', 'url': ''})

# v4l2sink refuses caps that leave these fields unfixed, and intervideosrc fixates without
# them — so the shim has to be there, and it has to be the SAME on both halves. Read it back
# out of each description rather than trusting caps_shim(): a one-sided edit is the failure
# this guards, and comparing the helper to itself could never see one.
shim_in_out = re.search(r'capssetter join=true caps=\S+', out)
shim_in_inp = re.search(r'capssetter join=true caps=\S+', inp)
check(bool(shim_in_out and shim_in_inp), 'both halves carry a caps shim')
eq(shim_in_out.group(0), shim_in_inp.group(0), 'and it is byte-identical on both sides')
for field in ('interlace-mode=progressive', 'pixel-aspect-ratio=1/1', 'multiview-mode=mono', 'colorimetry='):
    contains(shim_in_out.group(0), field, f'the shim fixes {field.rstrip("=")}')

# Matched, not searched for: `channel=hndi-in` contains the substring `channel=hndi`, so a
# `contains()` on the channel name would pass a pipeline whose two halves never meet.
out_ch = re.findall(r'channel=(\S+)', out)
in_ch = re.findall(r'channel=(\S+)', inp)
eq(out_ch, [m.CHANNEL], 'output: reads exactly the inter channel')
eq(in_ch, [m.CHANNEL], 'input: writes exactly the same inter channel')
contains(out, 'intervideosrc', 'output: starts at intervideosrc')
contains(out, 'v4l2sink name=v4l2 device=/dev/video10', 'output: ends at the loopback device')
contains(out, 'format=YUY2,width=1920,height=1080', 'output: the caps Chrome will see')
# Non-default values on purpose: asserting the shipped ones alone cannot tell a config that is
# read from one that is hard-coded.
elsewhere = node_from(conf_from('[input]\ndevice = 12\nwidth = 1280\nheight = 720\nfps = 30\nformat = yuy2\n')).out_desc()
contains(elsewhere, 'device=/dev/video12', 'output: a non-default device number is honoured')
contains(elsewhere, 'format=YUY2,width=1280,height=720,framerate=30/1', 'output: size and fps are honoured, format upper-cased')
contains(out, f'timeout={1500 * 1000000}', 'output: hold_ms reaches intervideosrc in nanoseconds')
contains(inp, 'ndi-name="KMINI-001 (HNDI-TEST)"', 'input: a discovered source selects by name')
contains(n.in_desc({'name': 'x', 'url': '10.0.0.5:5961'}), 'url-address="10.0.0.5:5961"',
         'input: a source with a url selects by url, skipping discovery')
contains(inp, 'bandwidth=100', 'input: highest is ndisrc bandwidth=100')
contains(inp, f'timeout={8000 + 5000}', 'input: ndisrc outlives dead_ms so the daemon reconnects first')
n.bandwidth = 'lowest'
contains(n.in_desc({'name': 'x', 'url': ''}), 'bandwidth=0', 'input: lowest is ndisrc bandwidth=0 (the proxy stream)')

nr = node_from(conf_from('[input]\nprofile = robust\n'))
ir = nr.in_desc({'name': 'x', 'url': ''})
contains(ir, f'min-threshold-time={100 * 1000000}', 'robust: the jitter buffer holds 100 ms back')
contains(ir, 'max-queue-length=8', 'robust: the deeper ndisrc queue reaches the pipeline')
check('min-threshold-time' not in inp, 'lowlatency: no jitter buffer in the pipeline at all')

eq(node_from(shipped)._pick(), None, 'nothing configured and nothing discovered picks nothing')
direct = node_from(conf_from('[input]\nsource = ndi://10.0.0.5:5961\n'))
eq(direct._pick(), {'name': 'ndi://10.0.0.5:5961', 'url': '10.0.0.5:5961'}, 'ndi:// is a direct connect')
bare = node_from(conf_from('[input]\nsource = 10.0.0.5:5961\n'))
eq(bare._pick(), {'name': '10.0.0.5:5961', 'url': '10.0.0.5:5961'}, 'bare ip:port is a direct connect')

# ── 4. bandwidth=auto, and the no-restart rule ────────────────────────────
section('bandwidth=auto — sustained trouble, not a blip')
a = node_from(conf_from('[input]\nbandwidth = auto\n'))
eq((a.mode, a.auto, a.bandwidth), ('auto', True, 'highest'), 'auto starts at highest')
a.state = 'stopped'
a._auto_bandwidth()
eq(a._bad, 0, 'while not running, bandwidth stays out of it (that is the reconnect path)')

a.state = 'running'
a.resolved = {'name': 'x', 'url': ''}
a._fps_baseline, a.fps_measured, a.stalled = 60.0, 0.0, True
a._last_bw_switch = 0.0                      # monotonic is far past 0 → dwell is satisfied
for _ in range(4):
    a._auto_bandwidth()
eq(a.bandwidth, 'highest', 'four bad seconds are a blip — still on highest')
a._auto_bandwidth()
eq(a.bandwidth, 'lowest', 'the fifth drops to the proxy stream')

a.stalled, a.fps_measured = False, 60.0
a._last_bw_switch = 0.0
for _ in range(29):
    a._auto_bandwidth()
eq(a.bandwidth, 'lowest', '29 clean seconds are not yet a recovery')
a._auto_bandwidth()
eq(a.bandwidth, 'highest', '30 clean seconds recover the full stream')

section('a source switch to what is already on air keeps the feed')
k = node_from(shipped)
k.state, k.resolved = 'running', {'name': 'KMINI-001 (HNDI-TEST)', 'url': ''}
k.set_source('HNDI-TEST', persist=False)
eq(k.restarts, 0, 're-naming the source that is already playing does not restart the input')
eq(k.resolved['name'], 'KMINI-001 (HNDI-TEST)', 'and the feed stays resolved to it')
k.set_source('REGIE', persist=False)
eq(k.restarts, 1, 'a genuinely different source does restart')

report('tests/node.py')
