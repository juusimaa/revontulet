#!/usr/bin/env python3
"""Calibrate the Kp-to-activity mapping against recorded nights (specs/003-aurora-outlook R7, SC-004).

DEVELOPMENT TOOL ONLY. For nights in the dark seasons of 2024-2026 it compares the band mapping
of the Kp that was actually observed (GFZ Potsdam definitive Kp, CC BY 4.0, credited in
calibration_common.py) with the highest FMI activity level of that night at each zone's station
(computed from FMI open data magnetometer archives, CC BY 4.0).

For each night (15:00-05:00 UTC) and station, the hours compared are the outlook's relevant
hours (contracts/outlook-rules.md section 1): the minutes at Dark (sun <= -12 deg) at the
station, or all minutes that are not too light if the night never reaches Dark. Observed Kp is
the highest block overlapping those minutes; the FMI level is the highest activity held for 15
consecutive minutes of them (calibration_common.SUSTAINED_MINUTES: the archive has single-sample
glitches that lift R for 10 minutes). Station-nights with R for fewer than 80% of those minutes
are left out.

Nights: the nights calibrate-soon.py cached (tools/.cache/nights/) plus nights spread over the
whole Kp range, so that each band sees quiet, active and storm nights: up to --per-bucket
nights per Kp bucket (max Kp of the night 0-2, 2-3, 3-4, 4-5, 5-6, 6+), chosen with a fixed seed.

Search: for each band, every `Possible from` and `Probable from` in thirds from 1 to 9
(Possible < Probable). The pair with the most agreeing station-nights wins; ties go to the pair
closest to the initial one.

Writes Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/kp-nights.json:
  [{"night", "zone", "band", "kp", "fmi"}]  (fmi: unlikely, possible or probable)

Usage:
  python3 tools/calibrate-kp.py [--per-bucket 12] [--no-fixtures]
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from datetime import date, datetime, timedelta, timezone

import calibration_common as cc

FIRST_NIGHT = date(2024, 9, 1)
LAST_NIGHT = date(2026, 10, 20)
DARK_MONTHS = {9, 10, 11, 12, 1, 2, 3}
BUCKETS = [(0, 2), (2.33, 3), (3.33, 4), (4.33, 5), (5.33, 6), (6.33, 9)]
INITIAL = {"north": (3, 5), "central": (4, 6), "south": (5, 7)}
SEED = 2026
MIN_COVERAGE = 0.8
EPSILON = 0.01


def level(kp: float, possible_from: float, probable_from: float) -> str:
    if kp >= probable_from - EPSILON:
        return "probable"
    if kp >= possible_from - EPSILON:
        return "possible"
    return "unlikely"


def station_nights(evening: date, kp_blocks) -> list[dict]:
    start, end = cc.night_window(evening)
    r = cc.night_r(evening)
    rows = []
    for code in cc.STATIONS:
        minutes = sorted(r[code])
        times = {m: datetime.fromtimestamp(m, timezone.utc) for m in minutes}
        dark = {m: cc.darkness_at(code, times[m]) for m in minutes}
        relevant = [m for m in minutes if dark[m] == "dark"] or [m for m in minutes if dark[m] != "tooLight"]
        if not relevant:
            continue
        values = [r[code][m] for m in relevant if r[code][m] is not None]
        if len(values) < MIN_COVERAGE * len(relevant):
            continue
        kp = cc.max_kp(kp_blocks, times[relevant[0]], times[relevant[-1]] + timedelta(minutes=1))
        if kp is None:
            continue
        fmi = cc.sustained_level([(m, r[code][m]) for m in relevant], code)
        rows.append({"night": f"{evening:%Y%m%d}", "zone": code, "band": cc.BAND_OF[code], "kp": kp, "fmi": fmi})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--per-bucket", type=int, default=12)
    ap.add_argument("--no-fixtures", action="store_true")
    args = ap.parse_args()

    kp_blocks = cc.gfz_kp()
    cached = {date(int(p.stem[:4]), int(p.stem[4:6]), int(p.stem[6:])) for p in (cc.CACHE / "nights").glob("*.json")}
    by_bucket: dict[int, list[date]] = {i: [] for i in range(len(BUCKETS))}
    d = FIRST_NIGHT
    while d <= LAST_NIGHT:
        if d.month in DARK_MONTHS:
            start, end = cc.night_window(d)
            night_kp = cc.max_kp(kp_blocks, start, end)
            if night_kp is not None:
                for i, (low, high) in enumerate(BUCKETS):
                    if low - EPSILON <= night_kp <= high + EPSILON:
                        by_bucket[i].append(d)
        d += timedelta(days=1)
    rng = random.Random(SEED)
    chosen = set(cached)
    for i, days in by_bucket.items():
        have = [d for d in days if d in chosen]
        rest = [d for d in days if d not in chosen]
        rng.shuffle(rest)
        chosen.update(rest[: max(0, args.per_bucket - len(have))])
    print(f"{len(chosen)} nights ({len(cached)} cached)", file=sys.stderr)

    rows = []
    for evening in sorted(chosen):
        try:
            rows += station_nights(evening, kp_blocks)
        except Exception as e:  # noqa: BLE001 -- an FMI gap skips the night
            print(f"  {evening}: skipped ({e})", file=sys.stderr)
    nights = sorted({r["night"] for r in rows})
    print(f"{len(rows)} station-nights over {len(nights)} nights")

    results = {}
    thirds = [round(1 + i / 3, 2) for i in range(25)]
    for band in cc.BANDS:
        band_rows = [r for r in rows if r["band"] == band]
        best = None
        for p in thirds:
            for q in thirds:
                if q <= p:
                    continue
                agree = sum(level(r["kp"], p, q) == r["fmi"] for r in band_rows)
                distance = abs(p - INITIAL[band][0]) + abs(q - INITIAL[band][1])
                key = (-agree, distance)
                if best is None or key < best[0]:
                    best = (key, p, q, agree)
        _, p, q, agree = best
        initial = sum(level(r["kp"], *INITIAL[band]) == r["fmi"] for r in band_rows)
        results[band] = {"possibleFrom": p, "probableFrom": q, "agree": agree, "of": len(band_rows),
                         "initialAgree": initial}
        print(f"{band:8s} possible from {p:.2f}  probable from {q:.2f}  agreement {agree}/{len(band_rows)}"
              f" = {agree / len(band_rows):.1%}  (initial {INITIAL[band]}: {initial / len(band_rows):.1%})")

    total = sum(r["agree"] for r in results.values())
    print(f"overall agreement {total}/{len(rows)} = {total / len(rows):.1%}")
    for kind in ("unlikely", "possible", "probable"):
        print(f"  FMI {kind}: {sum(1 for r in rows if r['fmi'] == kind)}")

    if not args.no_fixtures:
        path = cc.FIXTURES / "kp-nights.json"
        path.write_text("[\n" + ",\n".join(json.dumps(r) for r in rows) + "\n]\n")
        (cc.FIXTURES / "kp-thresholds.json").write_text(json.dumps(results, indent=1) + "\n")
        print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
