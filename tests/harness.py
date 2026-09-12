"""Import the HNdi input node on a machine that has no GStreamer.

`input/hndi-in` is the daemon. It is a stdlib + PyGObject script with no `.py` extension,
so nothing can `import` it the ordinary way, and on a dev box `import gi` fails outright.
This module solves both:

  * `load_daemon()` loads `input/hndi-in` as the module `hndi_in`, behind a stdlib-only
    stand-in for `gi` / `GLib` / `Gst`;
  * `check()` / `section()` / `report()` are the three-line test runner the suites use.

The stand-in is deliberately hostile: **every** attribute of `Gst` raises. So a test can
only ever exercise logic that does not touch GStreamer — config parsing, source matching,
the pipeline *description* strings, the bandwidth policy, the HTTP API. The moment a test
drifts into real pipeline territory it fails loudly instead of quietly pretending.

`GLib` is the exception, and only where the daemon uses it as plumbing: `MainLoop()` is
inert and `idle_add(fn, *a)` runs `fn` synchronously — which is what makes the API suite
able to assert on the effect of a `PUT /source` without a GLib main loop.
"""
import importlib.util
import logging
import os
import sys
import types
from importlib.machinery import SourceFileLoader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class _NoGst:
    """Stand-in for `Gst`: touching anything on it is an error, with a readable reason."""

    def __getattr__(self, name):
        raise RuntimeError(
            f'Gst.{name} touched, but this test harness has no GStreamer. '
            'Tests may only cover logic that does not build or run a pipeline.')


class _GLib:
    """Just enough GLib for the daemon to construct and for the API to be exercised."""

    class Error(Exception):
        pass

    PRIORITY_HIGH = 0

    @staticmethod
    def MainLoop(*a, **k):
        return types.SimpleNamespace(run=lambda: None, quit=lambda: None)

    @staticmethod
    def idle_add(fn, *a):
        fn(*a)          # synchronous on purpose: the API suite asserts on the effect
        return False

    @staticmethod
    def timeout_add(*a, **k):
        return 0

    @staticmethod
    def timeout_add_seconds(*a, **k):
        return 0

    @staticmethod
    def unix_signal_add(*a, **k):
        return 0


def load_daemon():
    """Return `input/hndi-in` as an imported module. Idempotent."""
    if 'hndi_in' in sys.modules:
        return sys.modules['hndi_in']
    gi = types.ModuleType('gi')
    gi.require_version = lambda *a, **k: None
    repository = types.ModuleType('gi.repository')
    repository.GLib = _GLib
    repository.Gst = _NoGst()
    gi.repository = repository
    sys.modules['gi'] = gi
    sys.modules['gi.repository'] = repository

    path = os.path.join(ROOT, 'input', 'hndi-in')
    loader = SourceFileLoader('hndi_in', path)
    spec = importlib.util.spec_from_loader('hndi_in', loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules['hndi_in'] = mod
    loader.exec_module(mod)
    # The daemon logs to stderr at INFO; a passing suite should say nothing but ok/FAIL.
    logging.getLogger('hndi-in').setLevel(logging.CRITICAL)
    return mod


# ── the runner ────────────────────────────────────────────────────────────
_failed = []
_total = 0


def section(title):
    print(f'\n-- {title}')


def check(cond, label, detail=''):
    global _total
    _total += 1
    if cond:
        print(f'   ok   {label}')
    else:
        print(f'   FAIL {label}' + (f'   ({detail})' if detail else ''))
        _failed.append(label)
    return bool(cond)


def eq(got, want, label):
    return check(got == want, label, f'got {got!r}, want {want!r}')


def contains(haystack, needle, label):
    return check(needle in haystack, label, f'{needle!r} not in {haystack!r}')


def report(title):
    if _failed:
        print(f'\n{title}: {len(_failed)}/{_total} FAILED')
        for f in _failed:
            print(f'  - {f}')
        sys.exit(1)
    print(f'\n{title}: {_total} checks ok')
    sys.exit(0)
