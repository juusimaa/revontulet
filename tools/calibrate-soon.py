#!/usr/bin/env python3
"""Calibrate the "soon" thresholds against recorded nights (specs/003-aurora-outlook R6, SC-003).

DEVELOPMENT TOOL ONLY. Replays NASA OMNI 1-minute solar wind (public domain) against FMI activity
computed from FMI open data magnetometer archives (CC BY 4.0) for nights in the dark seasons of
2024-2026, and searches the `possible`/`likely` Ey thresholds per band.

Nights (15:00-05:00 UTC) are chosen with GFZ definitive Kp (CC BY 4.0, see calibration_common.py):

  storm nights  Kp >= 5 in some block of the night; kept when a station of the band reached
                Probable while it was not too light, after the first hour of the night (a rise
                that was seen, not one already under way), and OMNI covers the night
  quiet nights  Kp <= 2 in every block of the night, and OMNI covers the night

The replay runs the soon rule every 5 minutes (the app's refresh cadence) from 15:00 to 05:00
UTC, on the samples the propagated product would have held then: observed at L1 at least
8 minutes before, at most an hour old. OMNI's timeshift gives the L1 time and its row time the
arrival. A rise is detected when the state is Possible or Likely at some step in the hour before
it up to 15 minutes before it (from onset - 75 min to onset - 15 min). The thresholds are chosen
on the storm nights' rises; rises on quiet nights (a Lapland station can still reach Probable at
Kp <= 2) are reported as "allRises" but not used. On quiet
nights, the share of dark replay steps (sun <= -12 deg at the band's reference station) with
Likely is counted.

Search: for each band, every `possible` from 0.5 to 8.0 mV/m in 0.25 steps, with `likely` twice
it as in the initial table. A pair qualifies when it meets SC-003 with one night to spare
(detections >= ceil(70% of the storm nights) + 1, quiet Likely <= 10% of dark steps). The band
gets the qualifying pair with the highest `possible`: the fewest Possible and Likely steps on
quiet nights while still seeing the rises coming. A band with fewer than MIN_BAND_STORMS storm
nights keeps the North pair scaled by the initial ratio between the bands.

Rejected ranking (first run, 2026-10-30): the fewest false Likely steps first. Every pair with a
low enough `likely` has none, so it pushed `possible` down to 1.25 in every band and ignored
latitude.

Writes Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/soon-nights/:
  nights.json      [{"night", "kind", "start", "end", "onset": {band: ISO or null}}]
  <YYYYMMDD>.csv   time,arrival,bz,speed,density (UTC, one row per L1 minute, empty = missing)

Usage:
  python3 tools/calibrate-soon.py [--storms 24] [--quiet 22] [--no-fixtures]
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import calibration_common as cc

FIRST_NIGHT = date(2024, 9, 1)
LAST_NIGHT = date(2026, 10, 20)
DARK_MONTHS = {9, 10, 11, 12, 1, 2, 3}
STEP = timedelta(minutes=5)
SAMPLE_LEAD = timedelta(minutes=90)
REFERENCE_STATION = {"north": "MUO", "central": "OUJ", "south": "TAR"}
INITIAL = {"north": (1.5, 3.0), "central": (2.5, 5.0), "south": (4.0, 8.0)}
MIN_BAND_STORMS = 8
MIN_OMNI_COVERAGE = 0.8
SEED = 2026


def evenings() -> list[date]:
    days = []
    d = FIRST_NIGHT
    while d <= LAST_NIGHT:
        if d.month in DARK_MONTHS:
            days.append(d)
        d += timedelta(days=1)
    return days


def onsets(evening: date) -> dict[str, str | None]:
    """Per band, the first minute a band station reached Probable, held for 15 minutes, while
    not too light (calibration_common.SUSTAINED_MINUTES: single-sample glitches do not count)."""
    start, end = cc.night_window(evening)
    r = cc.night_r(evening)
    result = {}
    for band, codes in cc.BANDS.items():
        first = None
        for code in codes:
            series = [(m, v) for m, v in sorted(r[code].items())
                      if cc.darkness_at(code, datetime.fromtimestamp(m, timezone.utc)) != "tooLight"]
            runs = cc.sustained_runs(series, code, "probable")
            if runs:
                t = datetime.fromtimestamp(runs[0], timezone.utc)
                if first is None or t < first:
                    first = t
        # A rise already under way in the first hour is not a rise the replay can see coming.
        result[band] = cc.iso(first) if first and first >= start + timedelta(hours=1) else None
    return result


def coverage(samples, start: datetime, end: datetime) -> float:
    minutes = {s[0] for s in samples if s[2] is not None and s[3] is not None and start <= s[0] <= end}
    return len(minutes) / ((end - start).total_seconds() / 60 + 1)


def drivers(samples, start: datetime, end: datetime) -> list[tuple[datetime, float | None]]:
    """[(now, median Ey or None)] every 5 minutes, from what the product held at that time."""
    result = []
    published = []
    i = 0
    now = start
    while now <= end:
        while i < len(samples) and samples[i][0] <= now - cc.LATENCY:
            published.append(samples[i])
            i += 1
        recent = [s for s in published[-90:] if s[0] >= now - timedelta(hours=1)]
        result.append((now, cc.soon_driver(recent, now)))
        now += STEP
    return result


def replay(night, possible: float, likely: float) -> list[tuple[datetime, str]]:
    """[(now, state)] every 5 minutes, with hysteresis from the previous step."""
    states = []
    previous = None
    for now, driver in night["drivers"]:
        state = cc.soon_classify(driver, possible, likely, previous)
        states.append((now, state))
        previous = state if state != "unknown" else None
    return states


def detected(states, onset: datetime) -> bool:
    return any(onset - timedelta(minutes=75) <= t <= onset - timedelta(minutes=15) and s in ("possible", "likely")
               for t, s in states)


def likely_share(night, states, band: str) -> tuple[int, int]:
    dark = [s for (_, s), is_dark in zip(states, night["dark"][band]) if is_dark]
    return sum(1 for s in dark if s == "likely"), len(dark)


def evaluate(band, possible, likely, storms, quiet):
    hits = sum(detected(replay(n, possible, likely), n["onset"][band]) for n in storms)
    false_likely = dark = 0
    for n in quiet:
        f, d = likely_share(n, replay(n, possible, likely), band)
        false_likely += f
        dark += d
    return hits, false_likely, dark


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--storms", type=int, default=24, help="storm nights to collect (North onsets)")
    ap.add_argument("--quiet", type=int, default=22, help="quiet nights to collect")
    ap.add_argument("--no-fixtures", action="store_true")
    args = ap.parse_args()

    kp = cc.gfz_kp()
    rng = random.Random(SEED)
    storm_candidates, quiet_candidates = [], []
    for evening in evenings():
        start, end = cc.night_window(evening)
        night_kp = [v for t, v in kp.items() if start - timedelta(hours=3) < t < end]
        if len(night_kp) < 5:
            continue
        if max(night_kp) >= 5:
            storm_candidates.append(evening)
        elif max(night_kp) <= 2:
            quiet_candidates.append(evening)
    rng.shuffle(storm_candidates)
    rng.shuffle(quiet_candidates)
    print(f"Candidates: {len(storm_candidates)} storm, {len(quiet_candidates)} quiet", file=sys.stderr)

    def load(evening: date, kind: str):
        start, end = cc.night_window(evening)
        samples = cc.omni(start - SAMPLE_LEAD, end)
        if coverage(samples, start - timedelta(hours=1), end) < MIN_OMNI_COVERAGE:
            print(f"  {evening}: OMNI coverage too low, skipped", file=sys.stderr)
            return None
        try:
            onset = onsets(evening)
        except Exception as e:  # noqa: BLE001 -- an FMI gap skips the night
            print(f"  {evening}: FMI failed ({e}), skipped", file=sys.stderr)
            return None
        steps = drivers(samples, start, end)
        return {"night": evening, "kind": kind, "start": start, "end": end, "samples": samples,
                "onset": {b: cc.parse_utc(o) if o else None for b, o in onset.items()},
                "drivers": steps,
                "dark": {b: [cc.darkness_at(REFERENCE_STATION[b], t) == "dark" for t, _ in steps] for b in cc.BANDS}}

    storms, quiet = [], []
    for evening in storm_candidates:
        if sum(1 for n in storms if n["onset"]["north"]) >= args.storms:
            break
        night = load(evening, "storm")
        if night and night["onset"]["north"]:
            storms.append(night)
            print(f"  storm {evening}: onsets {[(b, cc.iso(o)) for b, o in night['onset'].items() if o]}", file=sys.stderr)
    for evening in quiet_candidates:
        if len(quiet) >= args.quiet:
            break
        night = load(evening, "quiet")
        if night:
            quiet.append(night)
    print(f"Collected {len(storms)} storm and {len(quiet)} quiet nights", file=sys.stderr)

    results = {}
    for band in cc.BANDS:
        # The storm nights' rises (research R6). Rises on Kp <= 2 nights are reported below but
        # not used: counting them pushes the North pair to the bottom of the grid (0.5/1.0 mV/m),
        # which would say "may rise" on almost every night.
        band_storms = [n for n in storms if n["onset"][band]]
        if len(band_storms) < MIN_BAND_STORMS:
            results[band] = None
            print(f"{band}: only {len(band_storms)} storm nights, scaled from north")
            continue
        best = None
        needed = math.ceil(0.7 * len(band_storms)) + 1
        for possible in [x / 4 for x in range(2, 33)]:
            likely = possible * 2
            hits, false_likely, dark = evaluate(band, possible, likely, band_storms, quiet)
            share = false_likely / dark if dark else 0
            if hits >= needed and share <= 0.1:
                best = (possible, likely, hits / len(band_storms), share)
        results[band] = best and {"possible": best[0], "likely": best[1], "detection": best[2],
                                  "likelyShare": best[3], "storms": len(band_storms)}
        all_rises = [n for n in storms + quiet if n["onset"][band]]
        if best and len(all_rises) > len(band_storms):
            hits = sum(detected(replay(n, best[0], best[1]), n["onset"][band]) for n in all_rises)
            results[band]["allRises"] = len(all_rises)
            results[band]["allRisesDetection"] = hits / len(all_rises)
        print(f"{band}: {results[band]}")

    north = results["north"]
    if north is None:
        print("No North pair meets SC-003; thresholds not changed.")
        return 1
    for band in ("central", "south"):
        if results[band] is None:
            scale = INITIAL[band][0] / INITIAL["north"][0]
            results[band] = {"possible": north["possible"] * scale, "likely": north["likely"] * scale, "scaled": True}

    print("\nThresholds (mV/m):")
    for band, r in results.items():
        print(f"  {band:8s} possible {r['possible']:.2f}  likely {r['likely']:.2f}  {r}")

    if not args.no_fixtures:
        out = cc.FIXTURES / "soon-nights"
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob("*.csv"):
            old.unlink()
        index = []
        for n in sorted(storms + quiet, key=lambda n: n["night"]):
            index.append({"night": f"{n['night']:%Y%m%d}", "kind": n["kind"], "start": cc.iso(n["start"]),
                          "end": cc.iso(n["end"]),
                          "onset": {b: cc.iso(o) if o else None for b, o in n["onset"].items()}})
            lines = ["time,arrival,bz,speed,density"]
            for t, arrival, bz, speed, density in n["samples"]:
                cells = [cc.iso(t), cc.iso(arrival)] + ["" if v is None else f"{v:g}" for v in (bz, speed, density)]
                lines.append(",".join(cells))
            (out / f"{n['night']:%Y%m%d}.csv").write_text("\n".join(lines) + "\n")
        (out / "nights.json").write_text(json.dumps(index, indent=1) + "\n")
        (out / "thresholds.json").write_text(json.dumps(results, indent=1) + "\n")
        print(f"Fixtures written to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
