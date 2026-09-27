#!/usr/bin/env python3
"""End-to-end checks for Umbra through its CLI, against the real installed app.

Each check changes something in the running app, then reads `umbra state` (JSON) to confirm it
really happened. Your display values and settings are restored at the end, even when a check fails.

Usage:
  scripts/e2e/cli_e2e.py [--app ~/Applications/Umbra.app] [--disruptive]

--disruptive also runs BlackOut on an external monitor (it disconnects the screen for a moment).
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--app", default=os.path.expanduser("~/Applications/Umbra.app"))
parser.add_argument("--disruptive", action="store_true")
opts = parser.parse_args()
BIN = os.path.join(opts.app, "Contents/MacOS/Umbra")


def cli(*args, check=False):
    r = subprocess.run([BIN, *map(str, args)], capture_output=True, text=True, timeout=20)
    if check and r.returncode != 0:
        raise AssertionError(f"umbra {' '.join(map(str, args))} failed: {r.stdout.strip()} {r.stderr.strip()}")
    return r


def state():
    r = cli("state", check=True)
    return json.loads(r.stdout.strip())


def wait_for(pred, timeout=3.0, step=0.15):
    """Poll `umbra state` until pred(state) is true. Returns the last state."""
    end = time.time() + timeout
    st = state()
    while time.time() < end:
        if pred(st):
            return st
        time.sleep(step)
        st = state()
    return st


def near(a, b, tol=1.0):
    return abs(a - b) <= tol


def restart_app():
    subprocess.run(["pkill", "-x", "Umbra"], capture_output=True)
    time.sleep(1)
    # Skip the welcome screen and permission explainers so nothing waits on a click.
    subprocess.run(["open", opts.app, "--args", "-onboardingDone", "YES", "-askedAccessibility", "YES"], check=True)
    end = time.time() + 15
    while time.time() < end:
        try:
            if state()["displays"]:
                return
        except Exception:
            pass
        time.sleep(0.5)
    raise SystemExit("Umbra did not start or did not answer `umbra state`.")


results = []


def check(name):
    def wrap(fn):
        t0 = time.time()
        try:
            fn()
            results.append((name, True, "", time.time() - t0))
        except Exception as e:  # noqa: BLE001 - report every failure and keep going
            results.append((name, False, str(e), time.time() - t0))
        return fn
    return wrap


def assert_(cond, msg):
    if not cond:
        raise AssertionError(msg)


restart_app()
before = state()
builtin = next((d for d in before["displays"] if d["builtin"]), before["displays"][0])
ddc = next((d for d in before["displays"] if d["method"] == "ddc"), None)
externals = [d for d in before["displays"] if not d["builtin"]]
print(f"Displays: {', '.join(d['name'] + ' (' + d['method'] + ')' for d in before['displays'])}")

try:
    @check("state lists the connected displays")
    def _():
        st = state()
        assert_(len(st["displays"]) >= 1, "no displays in state")
        for d in st["displays"]:
            assert_(0 <= d["brightness"] <= 100, f"{d['name']} brightness out of range: {d['brightness']}")

    @check("brightness: set and read back")
    def _():
        cli("set", "builtin", "brightness", 35, check=True)
        st = wait_for(lambda s: near(next(d for d in s["displays"] if d["uuid"] == builtin["uuid"])["brightness"], 35))
        got = next(d for d in st["displays"] if d["uuid"] == builtin["uuid"])["brightness"]
        assert_(near(got, 35), f"expected 35, got {got}")

    if ddc:
        @check(f"contrast over DDC ({ddc['name']}): set and read back")
        def _():
            cli("set", ddc["name"], "contrast", 60, check=True)
            st = wait_for(lambda s: near(next(d for d in s["displays"] if d["uuid"] == ddc["uuid"])["contrast"], 60))
            got = next(d for d in st["displays"] if d["uuid"] == ddc["uuid"])["contrast"]
            assert_(near(got, 60), f"expected 60, got {got}")

    @check("below 0%: set and clear")
    def _():
        cli("set", "builtin", "subzero", 50, check=True)
        st = wait_for(lambda s: near(next(d for d in s["displays"] if d["uuid"] == builtin["uuid"])["subzero"], 0.5, 0.02))
        got = next(d for d in st["displays"] if d["uuid"] == builtin["uuid"])["subzero"]
        assert_(near(got, 0.5, 0.02), f"expected 0.5, got {got}")
        cli("set", "builtin", "subzero", 0, check=True)
        st = wait_for(lambda s: next(d for d in s["displays"] if d["uuid"] == builtin["uuid"])["subzero"] == 0)
        assert_(next(d for d in st["displays"] if d["uuid"] == builtin["uuid"])["subzero"] == 0, "sub-zero did not clear")

    @check("adaptive mode: switch to Sync and back")
    def _():
        cli("mode", "sync", check=True)
        assert_(wait_for(lambda s: s["mode"] == "sync")["mode"] == "sync", "mode did not change to sync")
        cli("mode", "manual", check=True)
        assert_(wait_for(lambda s: s["mode"] == "manual")["mode"] == "manual", "mode did not change back")

    @check("Night Mode dims and warms, then restores every display")
    def _():
        cli("set", "all", "brightness", 70, check=True)
        wait_for(lambda s: all(near(d["brightness"], 70) for d in s["displays"] if not d["blackedOut"]))
        cli("night", "on", check=True)
        st = wait_for(lambda s: s["night"] and all(d["brightness"] <= 20.5 for d in s["displays"] if not d["blackedOut"]))
        assert_(st["night"], "night flag is off")
        assert_(all(d["brightness"] <= 20.5 for d in st["displays"] if not d["blackedOut"]), "a display did not dim")
        assert_(all(d["blue"] < 1 for d in st["displays"] if not d["blackedOut"]), "colors did not warm")
        cli("night", "off", check=True)
        st = wait_for(lambda s: not s["night"] and all(near(d["brightness"], 70) for d in s["displays"] if not d["blackedOut"]))
        assert_(not st["night"], "night flag stayed on")
        for d in st["displays"]:
            assert_(near(d["brightness"], 70), f"{d['name']} not restored: {d['brightness']}")
            assert_(d["blue"] == 1, f"{d['name']} colors not restored")

    @check("Away mode: screens off with the Mac kept awake, then restored")
    def _():
        cli("set", "all", "brightness", 55, check=True)
        wait_for(lambda s: all(near(d["brightness"], 55) for d in s["displays"] if not d["blackedOut"]))
        cli("away", "now", check=True)
        # The stage flips at once; brightness then fades to 0 on a spring, so wait for both.
        st = wait_for(lambda s: s["away"] == "screens off" and all(d["brightness"] < 1 for d in s["displays"] if not d["blackedOut"]))
        assert_(st["away"] == "screens off", f"away stage is {st['away']}")
        assert_(all(d["brightness"] < 1 for d in st["displays"] if not d["blackedOut"]), "a screen stayed lit")
        held = subprocess.run(["pmset", "-g", "assertions"], capture_output=True, text=True).stdout
        assert_("Umbra Away mode" in held, "no keep-awake assertion while screens are off")
        cli("away", "off", check=True)
        st = wait_for(lambda s: s["away"] == "on" and all(near(d["brightness"], 55) for d in s["displays"] if not d["blackedOut"]))
        assert_(st["away"] == "on", f"away stage is {st['away']}")
        for d in st["displays"]:
            assert_(near(d["brightness"], 55), f"{d['name']} not restored: {d['brightness']}")
        held = subprocess.run(["pmset", "-g", "assertions"], capture_output=True, text=True).stdout
        assert_("Umbra Away mode" not in held, "keep-awake assertion was not released")

    @check("links: safe link works, BlackOut link is blocked")
    def _():
        subprocess.run(["open", "-g", "umbra://set?display=builtin&brightness=42"], check=True)
        st = wait_for(lambda s: near(next(d for d in s["displays"] if d["uuid"] == builtin["uuid"])["brightness"], 42))
        assert_(near(next(d for d in st["displays"] if d["uuid"] == builtin["uuid"])["brightness"], 42), "safe link did not set brightness")
        subprocess.run(["open", "-g", "umbra://blackout/all/on"], check=True)
        time.sleep(1.2)
        assert_(not any(d["blackedOut"] for d in state()["displays"]), "a link turned a display off")

    @check("CLI rejects commands that don't carry the app's token")
    def _():
        cli("set", "builtin", "brightness", 64, check=True)
        wait_for(lambda s: near(next(d for d in s["displays"] if d["uuid"] == builtin["uuid"])["brightness"], 64))
        src = ('import Foundation\n'
               'DistributedNotificationCenter.default().postNotificationName(Notification.Name("design.jordancampbell.umbra.cli"), object: nil, '
               'userInfo: ["args": ["set", "builtin", "brightness", "5"], "id": "e2e", "token": "wrong"], deliverImmediately: true)\n'
               'RunLoop.main.run(until: Date().addingTimeInterval(0.4))\n')
        with tempfile.TemporaryDirectory() as tmp:
            f = os.path.join(tmp, "main.swift")
            open(f, "w").write(src)
            subprocess.run(["swiftc", "-O", f, "-o", os.path.join(tmp, "forge")], check=True, capture_output=True)
            subprocess.run([os.path.join(tmp, "forge")], check=True)
        time.sleep(1)
        got = next(d for d in state()["displays"] if d["uuid"] == builtin["uuid"])["brightness"]
        assert_(near(got, 64), f"a forged command changed brightness to {got}")

    @check("unknown commands fail with a clear error")
    def _():
        r = cli("frobnicate")
        assert_(r.returncode == 1, f"exit code {r.returncode}")
        assert_("unknown command" in r.stdout, f"output: {r.stdout.strip()}")

    if opts.disruptive and externals:
        ext = externals[0]

        @check(f"BlackOut turns {ext['name']} off and back on")
        def _():
            cli("blackout", ext["name"], "on", check=True)
            st = wait_for(lambda s: next(d for d in s["displays"] if d["uuid"] == ext["uuid"])["blackedOut"], timeout=5)
            assert_(next(d for d in st["displays"] if d["uuid"] == ext["uuid"])["blackedOut"], "display did not turn off")
            cli("blackout", ext["name"], "off", check=True)
            st = wait_for(lambda s: not next(d for d in s["displays"] if d["uuid"] == ext["uuid"])["blackedOut"], timeout=6)
            assert_(not next(d for d in st["displays"] if d["uuid"] == ext["uuid"])["blackedOut"], "display did not come back")
finally:
    # Put everything back the way it was.
    cli("away", "off")
    cli("night", "off")
    cli("mode", before["mode"])
    for d in before["displays"]:
        cli("set", d["uuid"], "brightness", d["brightness"])
        cli("set", d["uuid"], "subzero", round(d["subzero"] * 100))
        if d["method"] == "ddc":
            cli("set", d["uuid"], "contrast", d["contrast"])

passed = sum(1 for r in results if r[1])
print()
for name, ok, msg, secs in results:
    print(f"{'PASS' if ok else 'FAIL'}  {name}  ({secs:.1f}s)" + (f"\n      {msg}" if msg else ""))
print(f"\n{passed}/{len(results)} checks passed")
os.makedirs("test-results", exist_ok=True)
with open("test-results/e2e-cli.json", "w") as f:
    json.dump([{"name": n, "passed": ok, "message": m, "seconds": round(s, 2)} for n, ok, m, s in results], f, indent=2)
sys.exit(0 if passed == len(results) else 1)
