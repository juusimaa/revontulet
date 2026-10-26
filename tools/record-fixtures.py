#!/usr/bin/env python3
"""Record FMI test fixtures for AuroraCore.

DEVELOPMENT TOOL ONLY. The shipped app never calls the FMI chart endpoint
(cdn.fmi.fi/apps/magnetic-disturbance-observation-graphs/...). This script uses
that endpoint only to record reference R values (and thresholds) that the
AuroraCore tests compare the on-device R calculation against (research R1/R2).

What it records (default output: Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/):

  magnetometer-<CODE>-<YYYYMMDDTHHMMZ>.csv
      FMI open data magnetometer observations (MAGN{X,Y,Z}_PT10S_AVG) for one
      station, columns time,x,y,z (ISO UTC; values as FMI gives them; empty
      for NaN), after a "# source: ..." comment line. Covers the window plus a
      10-minute lead-in before the window start, so every reference R point in
      the window has its full 10-minute input (research R1). Fetched for all
      stations one hour at a time and split by station (gml:pos within 0.01 deg).
      Compact CSV keeps fixtures small; these are input for R tests only.
  magnetometer-sample.xml
      Raw FMI XML for parser tests: one app-style 12-minute request ending at
      --end, reduced to Hankasalmi only. The stored query ignores narrow
      bbox/place filters, so the response is filtered locally: the header,
      footer and every kept <wfs:member> block are byte-for-byte as returned;
      only the other stations' members are removed and numberReturned/
      numberMatched are updated to the kept count.
  clouds-<YYYYMMDDTHHMMZ>.xml
      TotalCloudCover for Finland, 30 minutes ending at --end, as returned.
  reference-r.json
      FMI's published R values: [{"station", "time" (UTC, Z), "r"}], only the
      10 app stations, only inside the magnetometer window, latest
      (possibly partial) point per station dropped.
  reference-thresholds.json
      {code: {"yellow", "red"}} as currently shown on the FMI chart page.

The <YYYYMMDDTHHMMZ> stamp is the window end time.

Alert night mode (--alert-night START END, specs/002-aurora-alerts T016) writes to
Fixtures/alerts/<YYYYMMDD>/, where the date is the local (Europe/Helsinki) date of the
evening the night belongs to:

  magnetometer-<CODE>.csv
      As above, for START - 10 min .. END.
  clouds.csv
      TotalCloudCover for Finland, START - 30 min .. END, columns
      time,latitude,longitude,octas (value as FMI gives it; empty for NaN).
      Compact CSV instead of one XML response per 5-minute cycle (which would be
      hundreds of MB per night); the tests rebuild each request the service would
      make from these rows.
  night.json
      {"start", "end"} of the night window (UTC).
  reference-r.json
      FMI's published R inside the window, only when the FMI chart still covers it
      (it keeps about the last 24 hours); otherwise not written.

expected.json (the alerts the night must produce) is written separately by
tools/alert-reference.py, an independent implementation of the alert rules.

Python 3 standard library only (3.9+ for zoneinfo).

Usage:
  python3 tools/record-fixtures.py [--hours 3] [--end 2026-10-22T18:00:00Z] [--out DIR]
  python3 tools/record-fixtures.py --alert-night 2026-10-24T15:00:00Z 2026-10-25T05:00:00Z
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import re
import sys
import urllib.parse
import urllib.request
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

WFS_URL = "https://opendata.fmi.fi/wfs"
CHART_DATA_URL = "https://cdn.fmi.fi/apps/magnetic-disturbance-observation-graphs/serve-data.php"
CHART_PAGE_URL = "https://cdn.fmi.fi/apps/magnetic-disturbance-observation-graphs/index.php?embed=1&lang=fi"

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures"

HELSINKI = ZoneInfo("Europe/Helsinki")
POS_TOLERANCE = 0.01  # degrees
TIMEOUT = 120  # seconds per request

# code: (lat, lon, yellow, red) -- research.md R3
STATIONS = {
    "KEV": (69.756, 27.007, 55, 165),
    "KIL": (69.058, 20.775, 61, 210),
    "IVA": (68.559, 27.289, 72, 275),
    "MUO": (68.022, 23.520, 75, 300),
    "PEL": (66.904, 24.080, 73, 285),
    "RAN": (65.896, 26.409, 70, 240),
    "OUJ": (64.511, 27.227, 68, 200),
    "MEK": (62.774, 30.968, 64, 150),
    "HAN": (62.254, 26.597, 63, 140),
    "TAR": (58.264, 26.460, 55, 100),
}

MAG_PARAMS = "MAGNX_PT10S_AVG,MAGNY_PT10S_AVG,MAGNZ_PT10S_AVG"
MEMBER_RE = re.compile(r"<wfs:member>.*?</wfs:member>", re.S)
POS_RE = re.compile(r"<gml:pos>\s*([-0-9.]+)\s+([-0-9.]+)\s*</gml:pos>")
VALUE_RE = re.compile(r"<BsWfs:ParameterValue>([^<]*)</BsWfs:ParameterValue>")
LEAD_IN = timedelta(minutes=10)
SAMPLE_STATION = "HAN"
CSV_SOURCE = "# source: FMI open data fmi::observations::magnetometer::simple, CC BY 4.0"
TIME_RE = re.compile(r"<BsWfs:Time>([^<]+)</BsWfs:Time>")
PARAM_RE = re.compile(r"<BsWfs:ParameterName>([^<]+)</BsWfs:ParameterName>")


# ---------------------------------------------------------------- helpers

def iso(t: datetime) -> str:
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stamp(t: datetime) -> str:
    return t.astimezone(timezone.utc).strftime("%Y%m%dT%H%MZ")


def floor10(t: datetime) -> datetime:
    t = t.astimezone(timezone.utc).replace(microsecond=0)
    return t - timedelta(seconds=t.second % 10)


def parse_utc(s: str) -> datetime:
    t = datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    return t.astimezone(timezone.utc)


def fetch(url: str) -> bytes:
    """GET with gzip requested; returns decompressed body. Raises on non-200."""
    req = urllib.request.Request(url, headers={
        "Accept-Encoding": "gzip",
        "User-Agent": "revontulet-record-fixtures/1.0 (development tool)",
    })
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status} for {url}")
        body = resp.read()
        enc = (resp.headers.get("Content-Encoding") or "").lower()
    if enc == "gzip" or body[:2] == b"\x1f\x8b":
        body = gzip.decompress(body)
    elif enc == "deflate":
        body = zlib.decompress(body)
    return body


def wfs_url(storedquery: str, bbox: str, params: str, start: datetime, end: datetime) -> str:
    q = {
        "service": "WFS", "version": "2.0.0", "request": "getFeature",
        "storedquery_id": storedquery, "bbox": bbox, "parameters": params,
        "starttime": iso(start), "endtime": iso(end),
    }
    return WFS_URL + "?" + urllib.parse.urlencode(q, safe=":,")


def fetch_wfs(storedquery: str, bbox: str, params: str, start: datetime, end: datetime) -> str:
    url = wfs_url(storedquery, bbox, params, start, end)
    print(f"  GET {url}", file=sys.stderr)
    text = fetch(url).decode("utf-8")
    if "ExceptionReport" in text[:2000]:
        raise RuntimeError(f"FMI exception report:\n{text[:2000]}")
    return text


def station_for(lat: float, lon: float) -> str | None:
    for code, (slat, slon, _, _) in STATIONS.items():
        if abs(lat - slat) <= POS_TOLERANCE and abs(lon - slon) <= POS_TOLERANCE:
            return code
    return None


def write(path: Path, data: bytes | str, written: list) -> None:
    if isinstance(data, str):
        data = data.encode("utf-8")
    path.write_bytes(data)
    written.append(path)


# ---------------------------------------------------------------- magnetometer

def record_magnetometer(start: datetime, end: datetime, out: Path, written: list,
                        name: str = "magnetometer-{code}-{stamp}.csv") -> None:
    """Write one CSV per station covering [start - LEAD_IN, end]."""
    # per_station[code][time][param] = value text
    per_station: dict[str, dict[str, dict[str, str]]] = {c: {} for c in STATIONS}
    unknown_pos: set[tuple] = set()

    chunk_start = start - LEAD_IN
    while chunk_start <= end:
        # starttime/endtime are both inclusive; stop 10 s before the next chunk.
        chunk_end = min(chunk_start + timedelta(hours=1) - timedelta(seconds=10), end)
        text = fetch_wfs("fmi::observations::magnetometer::simple", "5,50,40,80",
                         MAG_PARAMS, chunk_start, chunk_end)
        for m in MEMBER_RE.finditer(text):
            block = m.group(0)
            pm = POS_RE.search(block)
            tm, pa, va = TIME_RE.search(block), PARAM_RE.search(block), VALUE_RE.search(block)
            if not (pm and tm and pa and va):
                continue
            lat, lon = float(pm.group(1)), float(pm.group(2))
            code = station_for(lat, lon)
            if code is None:
                unknown_pos.add((lat, lon))
                continue
            row = per_station[code].setdefault(tm.group(1).strip(), {})
            row.setdefault(pa.group(1).strip(), va.group(1).strip())
        chunk_start = chunk_end + timedelta(seconds=10)

    if unknown_pos:
        print(f"  ignored positions (not app stations): {sorted(unknown_pos)}", file=sys.stderr)

    def cell(v: str | None) -> str:
        return "" if v is None or v.lower() == "nan" else v

    for code, rows in per_station.items():
        if not rows:
            print(f"WARNING: no magnetometer data for {code}", file=sys.stderr)
            continue
        lines = [CSV_SOURCE, "time,x,y,z"]
        for t in sorted(rows):
            r = rows[t]
            lines.append(",".join([t] + [cell(r.get(p)) for p in
                                         ("MAGNX_PT10S_AVG", "MAGNY_PT10S_AVG", "MAGNZ_PT10S_AVG")]))
        write(out / name.format(code=code, stamp=stamp(end)), "\n".join(lines) + "\n", written)


def record_magnetometer_sample(end: datetime, out: Path, written: list) -> None:
    start = floor10(end - timedelta(minutes=12))
    text = fetch_wfs("fmi::observations::magnetometer::simple", "5,50,40,80",
                     MAG_PARAMS, start, end)
    kept = 0

    def keep(m: re.Match) -> str:
        nonlocal kept
        pm = POS_RE.search(m.group(0))
        if pm and station_for(float(pm.group(1)), float(pm.group(2))) == SAMPLE_STATION:
            kept += 1
            return m.group(0)
        return ""

    # Drop the whole "\n\t<wfs:member>...</wfs:member>\n\t" span of removed members.
    text = re.sub(r"[ \t]*<wfs:member>.*?</wfs:member>\s*",
                  lambda m: m.group(0) if keep(m) else "", text, flags=re.S)
    text = re.sub(r'numberReturned="\d+"', f'numberReturned="{kept}"', text, count=1)
    text = re.sub(r'numberMatched="\d+"', f'numberMatched="{kept}"', text, count=1)
    if kept == 0:
        print(f"WARNING: sample has no {SAMPLE_STATION} elements", file=sys.stderr)
    write(out / "magnetometer-sample.xml", text, written)


# ---------------------------------------------------------------- clouds

def record_clouds(end: datetime, out: Path, written: list) -> None:
    text = fetch_wfs("fmi::observations::weather::simple", "19,59.5,32,70.1",
                     "TotalCloudCover", end - timedelta(minutes=30), end)
    write(out / f"clouds-{stamp(end)}.xml", text, written)


# ---------------------------------------------------------------- reference R

def chart_ms_to_utc(ms: int, after: datetime | None = None) -> datetime:
    """Chart timestamps are Finnish wall-clock time encoded as if UTC.

    Read the epoch value as a naive wall-clock time, attach Europe/Helsinki
    (EET/EEST rules for that instant), convert to real UTC. In the repeated
    hour at the end of DST the earlier (EEST, fold=0) reading is used unless
    that would not be later than `after` (the previous point in the series),
    in which case the second (EET, fold=1) reading is used.
    """
    wall = datetime(1970, 1, 1) + timedelta(milliseconds=ms)
    t = wall.replace(tzinfo=HELSINKI).astimezone(timezone.utc)
    if after is not None and t <= after:
        t = wall.replace(tzinfo=HELSINKI, fold=1).astimezone(timezone.utc)
    return t


def record_reference_r(start: datetime, end: datetime, out: Path, written: list,
                       require_points: bool = False) -> dict[str, int]:
    data = json.loads(fetch(CHART_DATA_URL).decode("utf-8"))
    rows = []
    counts = {}
    latest_seen = None
    for code in STATIONS:
        series = (data.get(code) or {}).get("dataSeries") or []
        series = sorted(series, key=lambda p: p[0])[:-1]  # drop latest (maybe partial)
        n = 0
        prev = None
        for ms, r in series:
            t = prev = chart_ms_to_utc(int(ms), prev)
            if r is None or (isinstance(r, float) and math.isnan(r)):
                continue
            latest_seen = t if latest_seen is None or t > latest_seen else latest_seen
            if start <= t <= end:
                rows.append({"station": code, "time": iso(t), "r": r})
                n += 1
        counts[code] = n
    rows.sort(key=lambda d: (d["station"], d["time"]))
    if require_points and not rows:
        print("  FMI chart no longer covers this window; reference-r.json not written", file=sys.stderr)
        return counts
    write(out / "reference-r.json", json.dumps(rows, indent=1) + "\n", written)

    if latest_seen is not None:
        lag = datetime.now(timezone.utc) - latest_seen
        print(f"  latest kept chart point (UTC): {iso(latest_seen)}  (now - {lag})", file=sys.stderr)
        if abs(lag) > timedelta(minutes=30):
            print("WARNING: latest chart point is more than 30 min from now; "
                  "check the timezone conversion.", file=sys.stderr)
    return counts


def record_thresholds(out: Path, written: list) -> None:
    try:
        page = fetch(CHART_PAGE_URL).decode("utf-8", errors="replace")
        m = re.search(r"var\s+supportedStations\s*=\s*(\{.*?\});\s*\n", page, re.S)
        if not m:
            raise ValueError("supportedStations not found in chart page")
        stations = json.loads(m.group(1))
        result = {}
        for code in STATIONS:
            s = stations.get(code)
            if not s:
                print(f"WARNING: no thresholds for {code} on chart page", file=sys.stderr)
                continue
            result[code] = {"yellow": s["threshold1"], "red": s["threshold2"]}
    except Exception as e:  # noqa: BLE001 -- best effort, keep going
        print(f"WARNING: could not extract thresholds: {e}", file=sys.stderr)
        return

    write(out / "reference-thresholds.json", json.dumps(result, indent=1, sort_keys=True) + "\n", written)
    for code, (_, _, yellow, red) in STATIONS.items():
        got = result.get(code)
        if got and (got["yellow"] != yellow or got["red"] != red):
            print(f"WARNING: thresholds changed for {code}: bundled {yellow}/{red}, "
                  f"FMI now {got['yellow']}/{got['red']}", file=sys.stderr)


# ---------------------------------------------------------------- alert nights

def record_clouds_csv(start: datetime, end: datetime, out: Path, written: list) -> None:
    """TotalCloudCover rows for [start, end], fetched two hours at a time."""
    rows: set[tuple[str, str, str, str]] = set()
    chunk_start = start
    while chunk_start <= end:
        chunk_end = min(chunk_start + timedelta(hours=2) - timedelta(minutes=1), end)
        text = fetch_wfs("fmi::observations::weather::simple", "19,59.5,32,70.1",
                         "TotalCloudCover", chunk_start, chunk_end)
        for m in MEMBER_RE.finditer(text):
            block = m.group(0)
            pm, tm, va = POS_RE.search(block), TIME_RE.search(block), VALUE_RE.search(block)
            if not (pm and tm and va):
                continue
            value = va.group(1).strip()
            rows.add((tm.group(1).strip(), pm.group(1), pm.group(2), "" if value.lower() == "nan" else value))
        chunk_start = chunk_end + timedelta(minutes=1)
    lines = ["# source: FMI open data fmi::observations::weather::simple, CC BY 4.0",
             "time,latitude,longitude,octas"]
    lines += [",".join(r) for r in sorted(rows)]
    write(out / "clouds.csv", "\n".join(lines) + "\n", written)


def record_alert_night(start: datetime, end: datetime, out_root: Path, written: list) -> Path:
    evening = (start.astimezone(HELSINKI) - timedelta(hours=12)).date()
    out = out_root / "alerts" / evening.strftime("%Y%m%d")
    out.mkdir(parents=True, exist_ok=True)
    print(f"Alert night {iso(start)} .. {iso(end)}  ->  {out}", file=sys.stderr)
    print("Magnetometer (per station)...", file=sys.stderr)
    record_magnetometer(start, end, out, written, name="magnetometer-{code}.csv")
    print("Clouds...", file=sys.stderr)
    record_clouds_csv(start - timedelta(minutes=30), end, out, written)
    print("Reference R...", file=sys.stderr)
    record_reference_r(start, end, out, written, require_points=True)
    write(out / "night.json", json.dumps({"start": iso(start), "end": iso(end)}, indent=1) + "\n", written)
    return out


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--hours", type=float, default=3.0,
                    help="magnetometer window length in hours (fractions allowed, default 3)")
    ap.add_argument("--end", type=parse_utc, default=None,
                    help="window end, ISO 8601 UTC (default: now - 2 min, floored to 10 s)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT,
                    help=f"output directory (default: {DEFAULT_OUT.relative_to(REPO_ROOT)})")
    ap.add_argument("--alert-night", nargs=2, type=parse_utc, metavar=("START", "END"),
                    help="record one night for the alert tests (ISO 8601 UTC)")
    args = ap.parse_args()

    if args.alert_night:
        start, end = (floor10(t) for t in args.alert_night)
        written: list[Path] = []
        record_alert_night(start, end, args.out, written)
        print("\nFiles written:")
        for p in written:
            print(f"  {p.stat().st_size:>10,d}  {p}")
        return 0

    end = floor10(args.end or (datetime.now(timezone.utc) - timedelta(minutes=2)))
    start = floor10(end - timedelta(hours=args.hours))
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    print(f"Window: {iso(start)} .. {iso(end)}  ->  {out}", file=sys.stderr)
    print("Magnetometer (per station)...", file=sys.stderr)
    record_magnetometer(start, end, out, written)
    print("Magnetometer sample...", file=sys.stderr)
    record_magnetometer_sample(end, out, written)
    print("Clouds...", file=sys.stderr)
    record_clouds(end, out, written)
    print("Reference R...", file=sys.stderr)
    counts = record_reference_r(start, end, out, written)
    print("Thresholds...", file=sys.stderr)
    record_thresholds(out, written)

    print("\nFiles written:")
    for p in written:
        print(f"  {p.stat().st_size:>10,d}  {p}")
    print("\nReference R points per station:")
    for code, n in counts.items():
        print(f"  {code}: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
