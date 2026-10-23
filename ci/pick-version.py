#!/usr/bin/env python3
"""Which Linux version should LuxOS ship now? ("as new as possible, but stable")

Reads https://www.kernel.org/releases.json and the tags already released in this repository and prints
shell assignments for the workflow:  version=7.2.12  tag=v7.2.12-1  build=true|false  reason="..."

Policy:
  - Only kernel.org "stable" and "longterm" releases that are not end-of-life (never mainline -rc).
  - A new stable series (e.g. 7.3) is taken once it has at least MIN_PATCH point releases (7.3.3):
    the first point releases fix most regressions found after the .0 release.
  - Until then the series LuxOS already ships keeps getting its newest point release (security and
    bug fixes are never held back).
  - Never go back to an older series (no downgrade from 7.2 to 6.18).
  - Each version is built once per recipe revision (tag v<version>-<pkgrel>).

  ci/pick-version.py [--releases FILE] [--tags FILE] [--pkgrel N] [--force VERSION]
"""
import argparse
import json
import sys
import urllib.request

MIN_PATCH = 3
RELEASES_URL = "https://www.kernel.org/releases.json"


def vtuple(v):
    parts = v.split(".")
    if not all(p.isdigit() for p in parts):
        return None
    t = tuple(int(p) for p in parts)
    return t + (0,) * (3 - len(t))


def series(t):
    return t[:2]


def choose(releases, tags):
    """(version, reason) from releases.json entries and released tag names."""
    usable = []
    for r in releases:
        if r.get("moniker") not in ("stable", "longterm") or r.get("iseol"):
            continue
        t = vtuple(r.get("version", ""))
        if t:
            usable.append((t, r["version"], r.get("moniker")))
    if not usable:
        raise SystemExit("no usable stable release in releases.json")
    usable.sort(reverse=True)
    newest_t, newest_v, _ = usable[0]

    shipped = []
    for tag in tags:
        if tag.startswith("v") and "-" in tag:
            t = vtuple(tag[1:].split("-", 1)[0])
            if t:
                shipped.append(t)
    current = max(shipped) if shipped else None

    by_series = {}
    for t, v, _m in usable:
        by_series.setdefault(series(t), (t, v))   # newest point release of each series (sorted desc)

    if newest_t[2] >= MIN_PATCH:
        target, why = (newest_t, newest_v), f"newest stable series {newest_t[0]}.{newest_t[1]} is mature (.{newest_t[2]})"
    elif current and series(current) in by_series:
        target = by_series[series(current)]
        why = (f"{newest_v} is too fresh (< .{MIN_PATCH}); keeping series {current[0]}.{current[1]} "
               f"with its newest point release")
    elif current is None:
        older = [x for x in usable if series(x[0]) < series(newest_t) and x[0][2] >= MIN_PATCH]
        if older:
            target = (older[0][0], older[0][1])
            why = f"first build: {newest_v} is too fresh, starting with {older[0][1]}"
        else:
            target, why = (newest_t, newest_v), "first build: no mature older series, taking the newest"
    else:
        # the series LuxOS ships is end-of-life and the newest one is still fresh: security first
        target, why = (newest_t, newest_v), f"series {current[0]}.{current[1]} reached end of life"

    if current and series(target[0]) < series(current):
        same = by_series.get(series(current))
        target = same or (newest_t, newest_v)
        why += "; no downgrade to an older series"
    return target[1], why


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--releases")
    ap.add_argument("--tags", help="file with one released tag per line")
    ap.add_argument("--pkgrel", default="1")
    ap.add_argument("--force", default="", help="build this version even if it exists")
    a = ap.parse_args()
    if a.releases:
        with open(a.releases) as f:
            data = json.load(f)
    else:
        with urllib.request.urlopen(RELEASES_URL, timeout=30) as r:
            data = json.load(r)
    tags = []
    if a.tags:
        with open(a.tags) as f:
            tags = [x.strip() for x in f if x.strip()]
    if a.force:
        if not vtuple(a.force):
            raise SystemExit(f"invalid version {a.force!r}")
        version, why, build = a.force, "forced by hand", True
    else:
        version, why = choose(data.get("releases", []), tags)
        build = f"v{version}-{a.pkgrel}" not in tags
    print(f"version={version}")
    print(f"tag=v{version}-{a.pkgrel}")
    print(f"build={'true' if build else 'false'}")
    print("reason=" + json.dumps(why if build else why + " (already released)"))


if __name__ == "__main__":
    sys.exit(main())
