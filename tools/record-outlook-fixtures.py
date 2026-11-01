#!/usr/bin/env python3
"""Record NOAA SWPC and FMI forecast test fixtures for the aurora outlook.

DEVELOPMENT TOOL ONLY (specs/003-aurora-outlook research R10). Tests never touch the
network; this script records what they read, once, by hand.

What it records (default output: Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/):

  solar-wind-<quiet|active>.json
      products/geospace/propagated-solar-wind-1-hour.json as returned. The live product
      only holds the last hour, so the name says what the hour looked like: pass
      --solar-wind-as active on an active hour. Without an active recording,
      solar-wind-active.json is derived from the quiet one (Bz turned southward by
      10 nT, speed raised by 250 km/s) and marked as synthetic in README.md.
  solar-wind-gaps.json
      Derived from the recorded hour: nulls in Bz, speed and density in some rows, one
      row without time_tag and one duplicated minute (with a different value, which the
      parser must keep because it is the last one).
  kp-forecast.json
      products/noaa-planetary-k-index-forecast.json as returned (array of objects).
  kp-forecast-old-shape.json
      Hand-made from kp-forecast.json in SWPC's earlier shape: an array of arrays with a
      header row, values as strings, time_tag with a space instead of "T".
  alerts.json
      products/alerts.json, trimmed to every geomagnetic storm watch message (WATA..,
      including cancellations) plus the first few other messages. The script warns if
      there is no G1 watch, G2 watch or CANCEL WATCH among them.
  cloud-forecast.xml
      FMI fmi::forecast::edited::weather::scandinavia::point::simple with all ten station
      positions from stations.json, parameters=TotalCloudCover, timestep=60, as returned.
  noaa-404.txt
      The body SWPC returns for a retired product (the legacy solar-wind mag file).
  noaa-malformed.json
      The recorded solar wind file cut off in the middle.

--compare-kp (research R2 open point) does not write fixtures: it fetches the JSON Kp
forecast and text/3-day-forecast.txt and appends both products' predicted blocks to a
CSV (default tools/.cache/kp-compare.csv), so the two can be compared over a few days.

Python 3 standard library only (3.9+).

Usage:
  python3 tools/record-outlook-fixtures.py [--out DIR] [--solar-wind-as quiet|active]
  python3 tools/record-outlook-fixtures.py --only solar-wind --solar-wind-as active
  python3 tools/record-outlook-fixtures.py --compare-kp [--csv FILE]
"""

from __future__ import annotations

import argparse
import copy
import csv
import gzip
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zlib
from datetime import datetime, timezone
from pathlib import Path

SWPC = "https://services.swpc.noaa.gov"
SOLAR_WIND_URL = f"{SWPC}/products/geospace/propagated-solar-wind-1-hour.json"
KP_FORECAST_URL = f"{SWPC}/products/noaa-planetary-k-index-forecast.json"
ALERTS_URL = f"{SWPC}/products/alerts.json"
RETIRED_URL = f"{SWPC}/products/solar-wind/mag-1-day.json"
THREE_DAY_URL = f"{SWPC}/text/3-day-forecast.txt"
WFS_URL = "https://opendata.fmi.fi/wfs"
CLOUD_QUERY = "fmi::forecast::edited::weather::scandinavia::point::simple"

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook"
STATIONS_JSON = REPO_ROOT / "Packages/AuroraCore/Sources/AuroraCore/Resources/stations.json"
DEFAULT_CSV = REPO_ROOT / "tools/.cache/kp-compare.csv"

TIMEOUT = 120  # seconds per request
OTHER_ALERTS_KEPT = 5
WATCH_CODE_RE = re.compile(r"Space Weather Message Code: WATA\d\d")


# ---------------------------------------------------------------- helpers

def fetch(url: str, allow_error: bool = False) -> tuple[bytes, int]:
    """GET with gzip requested; returns the decompressed body and the status."""
    req = urllib.request.Request(url, headers={
        "Accept-Encoding": "gzip",
        "User-Agent": "revontulet-record-outlook-fixtures/1.0 (development tool)",
    })
    print(f"  GET {url}", file=sys.stderr)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            status, body, enc = resp.status, resp.read(), resp.headers.get("Content-Encoding")
    except urllib.error.HTTPError as e:
        if not allow_error:
            raise
        status, body, enc = e.code, e.read(), e.headers.get("Content-Encoding")
    enc = (enc or "").lower()
    if enc == "gzip" or body[:2] == b"\x1f\x8b":
        body = gzip.decompress(body)
    elif enc == "deflate":
        body = zlib.decompress(body)
    if status != 200 and not allow_error:
        raise RuntimeError(f"HTTP {status} for {url}")
    return body, status


def write(path: Path, data: bytes | str, written: list) -> None:
    if isinstance(data, str):
        data = data.encode("utf-8")
    path.write_bytes(data)
    written.append(path)


def compact_rows(rows: list) -> str:
    """One JSON row per line, so the fixtures diff well."""
    return "[\n" + ",\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n]\n"


# ---------------------------------------------------------------- solar wind

def record_solar_wind(name: str, out: Path, written: list) -> list:
    body, _ = fetch(SOLAR_WIND_URL)
    rows = json.loads(body)
    if not rows or "time_tag" not in rows[0]:
        raise RuntimeError("unexpected propagated solar wind header")
    write(out / f"solar-wind-{name}.json", body, written)
    return rows


def synthesize_active(rows: list, out: Path, written: list) -> None:
    header = rows[0]
    bz, speed = header.index("bz"), header.index("speed")
    active = [header]
    # Arrival times are kept as recorded.
    for row in rows[1:]:
        row = list(row)
        if row[bz] is not None:
            row[bz] = round(-abs(row[bz]) - 10, 2)
        if row[speed] is not None:
            row[speed] = round(row[speed] + 250, 1)
        active.append(row)
    write(out / "solar-wind-active.json", compact_rows(active), written)


def derive_gaps(rows: list, out: Path, written: list) -> None:
    header = rows[0]
    rows = copy.deepcopy(rows)
    time, bz, speed, density = (header.index(c) for c in ("time_tag", "bz", "speed", "density"))
    body = rows[1:]
    for i in range(3, len(body), 7):
        body[i][bz] = None
    for i in range(5, len(body), 11):
        body[i][speed] = None
    for i in range(2, len(body), 4):
        body[i][density] = None
    body[len(body) // 2][time] = None
    duplicate = list(body[-3])
    if duplicate[bz] is not None:
        duplicate[bz] = round(duplicate[bz] + 1.5, 2)
    body.insert(len(body) - 2, duplicate)
    write(out / "solar-wind-gaps.json", compact_rows([header] + body), written)


# ---------------------------------------------------------------- Kp forecast

def record_kp_forecast(out: Path, written: list) -> list:
    body, _ = fetch(KP_FORECAST_URL)
    blocks = json.loads(body)
    if not blocks or not isinstance(blocks[0], dict):
        print("WARNING: the Kp forecast is not an array of objects any more", file=sys.stderr)
    write(out / "kp-forecast.json", body, written)
    return blocks


def write_old_shape(blocks: list, out: Path, written: list) -> None:
    rows = [["time_tag", "kp", "observed", "noaa_scale"]]
    for b in blocks:
        rows.append([b["time_tag"].replace("T", " "), f"{b['kp']:.2f}", b["observed"], b.get("noaa_scale")])
    write(out / "kp-forecast-old-shape.json", compact_rows(rows), written)


# ---------------------------------------------------------------- alerts

def record_alerts(out: Path, written: list) -> None:
    body, _ = fetch(ALERTS_URL)
    messages = json.loads(body)
    watches = [m for m in messages if WATCH_CODE_RE.search(m.get("message", ""))]
    others = [m for m in messages if m not in watches][:OTHER_ALERTS_KEPT]
    kept = [m for m in messages if m in watches or m in others]  # keep the feed's order
    text = "\n".join(m["message"] for m in watches)
    for label, needle in (("G1 watch", "WATA20"), ("G2 watch", "WATA30"), ("cancellation", "CANCEL WATCH:")):
        if needle not in text:
            print(f"WARNING: alerts.json has no {label} ({needle}) today", file=sys.stderr)
    write(out / "alerts.json", json.dumps(kept, indent=1, ensure_ascii=False) + "\n", written)


# ---------------------------------------------------------------- FMI cloud forecast

def cloud_forecast_url() -> str:
    stations = json.loads(STATIONS_JSON.read_text())
    query = [
        ("service", "WFS"), ("version", "2.0.0"), ("request", "getFeature"),
        ("storedquery_id", CLOUD_QUERY),
    ]
    query += [("latlon", f"{s['latitude']},{s['longitude']}") for s in stations]
    query += [("parameters", "TotalCloudCover"), ("timestep", "60")]
    return WFS_URL + "?" + urllib.parse.urlencode(query, safe=":,")


def record_cloud_forecast(out: Path, written: list) -> None:
    body, _ = fetch(cloud_forecast_url())
    if b"ExceptionReport" in body[:2000]:
        raise RuntimeError(f"FMI exception report:\n{body[:2000].decode()}")
    write(out / "cloud-forecast.xml", body, written)


# ---------------------------------------------------------------- failures

def record_failures(solar_wind: list, out: Path, written: list) -> None:
    body, status = fetch(RETIRED_URL, allow_error=True)
    if status != 404:
        print(f"WARNING: {RETIRED_URL} returned {status}, not 404", file=sys.stderr)
    write(out / "noaa-404.txt", body, written)
    text = compact_rows(solar_wind)
    write(out / "noaa-malformed.json", text[: len(text) // 2], written)


# ---------------------------------------------------------------- R2 cross-check

MONTHS = {m: i for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], 1)}


def three_day_blocks(text: str) -> tuple[str, list[tuple[str, float]]]:
    """Predicted (time_tag, kp) blocks from the 3-day forecast's Kp table."""
    issued = re.search(r":Issued: (\d{4}) (\w{3}) (\d{2}) (\d{4}) UTC", text)
    if not issued:
        raise RuntimeError("3-day forecast without :Issued:")
    year = int(issued.group(1))
    issue_month = MONTHS[issued.group(2)]
    table = re.search(r"NOAA Kp index breakdown.*?\n\s*\n(.*?)\n\s*\n", text, re.S)
    if not table:
        raise RuntimeError("3-day forecast without a Kp table")
    lines = table.group(1).splitlines()
    days = re.findall(r"(\w{3}) (\d{2})", lines[0])
    blocks = []
    for line in lines[1:]:
        m = re.match(r"\s*(\d{2})-\d{2}UT\s+(.*)", line)
        if not m:
            continue
        values = re.findall(r"(\d+(?:\.\d+)?)", re.sub(r"\(G\d\)", "", m.group(2)))
        for (month, day), value in zip(days, values):
            y = year + 1 if MONTHS[month] < issue_month - 6 else year
            blocks.append((f"{y:04d}-{MONTHS[month]:02d}-{int(day):02d}T{m.group(1)}:00:00", float(value)))
    return issued.group(0), sorted(blocks)


def compare_kp(path: Path) -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    json_blocks = {b["time_tag"]: b["kp"] for b in json.loads(fetch(KP_FORECAST_URL)[0])
                   if b.get("observed") == "predicted"}
    issued, text_blocks = three_day_blocks(fetch(THREE_DAY_URL)[0].decode("utf-8", errors="replace"))
    path.parent.mkdir(parents=True, exist_ok=True)
    new = not path.exists()
    with path.open("a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["fetched", "text_issued", "block", "json_kp", "text_kp", "difference"])
        for block, text_kp in text_blocks:
            json_kp = json_blocks.get(block)
            diff = "" if json_kp is None else f"{json_kp - text_kp:+.2f}"
            w.writerow([now, issued, block, "" if json_kp is None else json_kp, text_kp, diff])
            print(f"  {block}  json {json_kp!s:>5}  text {text_kp:>5}  {diff}")
    print(f"Appended to {path}")


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT,
                    help=f"output directory (default: {DEFAULT_OUT.relative_to(REPO_ROOT)})")
    ap.add_argument("--solar-wind-as", choices=["quiet", "active"], default="quiet",
                    help="name for the recorded solar wind hour (default quiet)")
    ap.add_argument("--only", choices=["solar-wind"],
                    help="record only the named input")
    ap.add_argument("--compare-kp", action="store_true",
                    help="log the JSON and text Kp forecasts side by side (research R2)")
    ap.add_argument("--csv", type=Path, default=DEFAULT_CSV, help="CSV for --compare-kp")
    args = ap.parse_args()

    if args.compare_kp:
        compare_kp(args.csv)
        return 0

    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    print("Solar wind...", file=sys.stderr)
    rows = record_solar_wind(args.solar_wind_as, out, written)
    if args.solar_wind_as == "quiet":
        derive_gaps(rows, out, written)
        if not (out / "solar-wind-active.json").exists():
            synthesize_active(rows, out, written)
            print("NOTE: solar-wind-active.json is synthetic; re-record it on an active hour "
                  "with --only solar-wind --solar-wind-as active", file=sys.stderr)

    if args.only is None:
        print("Kp forecast...", file=sys.stderr)
        write_old_shape(record_kp_forecast(out, written), out, written)
        print("Alerts...", file=sys.stderr)
        record_alerts(out, written)
        print("FMI cloud forecast...", file=sys.stderr)
        record_cloud_forecast(out, written)
        print("Failure bodies...", file=sys.stderr)
        record_failures(rows, out, written)

    print("\nFiles written:")
    for p in written:
        print(f"  {p.stat().st_size:>10,d}  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
