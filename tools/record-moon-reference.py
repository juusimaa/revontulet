#!/usr/bin/env python3
"""Record moon reference values from JPL Horizons for MoonPositionTests.

DEVELOPMENT TOOL ONLY (specs/003-aurora-outlook research R4). JPL Horizons is a US
government service; its output is public domain. Tests never call it; they read the
fixture this script writes.

For Kevo (KEV), Oulujärvi (OUJ) and Tartu (TAR), on each day in DAYS, it asks Horizons
for an observer table (topocentric, airless apparent elevation, illuminated fraction) in
10-minute steps and keeps:

  - the values at 00, 06, 12 and 18 UTC, and
  - every step closest to a moonrise or moonset (elevation changing sign), so the
    reference covers the horizon, where parallax matters most.

The days are a new moon (2026-11-09), a first quarter (2026-11-17), a full moon
(2026-11-24), polar night at Kevo (2026-12-21) and a spring date (2026-03-15).

Writes Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/moon-reference.json:
  [{"station", "latitude", "longitude", "time" (ISO UTC), "altitude" (deg),
    "illuminatedFraction" (0...1)}]

Python 3 standard library only.

Usage:
  python3 tools/record-moon-reference.py [--out FILE]
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

HORIZONS_URL = "https://ssd.jpl.nasa.gov/api/horizons.api"
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/moon-reference.json"
TIMEOUT = 120

# code: (lat, lon), as in stations.json
STATIONS = {
    "KEV": (69.756, 27.007),
    "OUJ": (64.511, 27.227),
    "TAR": (58.264, 26.460),
}
DAYS = ["2026-03-15", "2026-11-09", "2026-11-17", "2026-11-24", "2026-12-21"]
FIXED_HOURS = {0, 6, 12, 18}


def iso(t: datetime) -> str:
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def ephemeris(lat: float, lon: float, day: str) -> list[tuple[datetime, float, float]]:
    """(time, elevation, illuminated fraction) every 10 minutes over one UTC day."""
    start = datetime.fromisoformat(day).replace(tzinfo=timezone.utc)
    stop = start + timedelta(days=1)
    params = {
        "format": "json",
        "COMMAND": "'301'",
        "OBJ_DATA": "'NO'",
        "MAKE_EPHEM": "'YES'",
        "EPHEM_TYPE": "'OBSERVER'",
        "CENTER": "'coord@399'",
        "COORD_TYPE": "'GEODETIC'",
        "SITE_COORD": f"'{lon},{lat},0'",
        "START_TIME": f"'{start:%Y-%m-%d %H:%M}'",
        "STOP_TIME": f"'{stop:%Y-%m-%d %H:%M}'",
        "STEP_SIZE": "'10m'",
        "QUANTITIES": "'4,10'",
        "APPARENT": "'AIRLESS'",
        "ANG_FORMAT": "'DEG'",
        "CSV_FORMAT": "'YES'",
        "TIME_DIGITS": "'MINUTES'",
    }
    url = HORIZONS_URL + "?" + urllib.parse.urlencode(params)
    print(f"  GET {url}", file=sys.stderr)
    with urllib.request.urlopen(url, timeout=TIMEOUT) as resp:
        result = json.loads(resp.read())["result"]
    body = result.split("$$SOE", 1)[1].split("$$EOE", 1)[0]
    rows = []
    for line in body.strip().splitlines():
        cells = [c.strip() for c in line.split(",")]
        # Date, solar-presence flag, lunar-presence flag, azimuth, elevation, illumination %
        t = datetime.strptime(cells[0], "%Y-%b-%d %H:%M").replace(tzinfo=timezone.utc)
        rows.append((t, float(cells[4]), float(cells[5]) / 100))
    return rows


def pick(rows: list[tuple[datetime, float, float]]) -> list[tuple[datetime, float, float]]:
    chosen = {r[0]: r for r in rows if r[0].minute == 0 and r[0].hour in FIXED_HOURS}
    for a, b in zip(rows, rows[1:]):
        if (a[1] > 0) != (b[1] > 0):
            nearest = a if abs(a[1]) <= abs(b[1]) else b
            chosen[nearest[0]] = nearest
    return [chosen[t] for t in sorted(chosen)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    entries = []
    for code, (lat, lon) in STATIONS.items():
        for day in DAYS:
            for t, altitude, fraction in pick(ephemeris(lat, lon, day)):
                entries.append({
                    "station": code, "latitude": lat, "longitude": lon, "time": iso(t),
                    "altitude": altitude, "illuminatedFraction": round(fraction, 5),
                })
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("[\n" + ",\n".join(json.dumps(e, ensure_ascii=False) for e in entries) + "\n]\n")
    horizon = sum(1 for e in entries if abs(e["altitude"]) < 2)
    print(f"Wrote {len(entries)} entries ({horizon} within 2° of the horizon) to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
