"""Shared data access for tools/calibrate-soon.py and tools/calibrate-kp.py.

DEVELOPMENT TOOL ONLY (specs/003-aurora-outlook research R6, R7). Downloads are cached in
tools/.cache/ (not committed):

  nights/<YYYYMMDD>.json  R per station every minute, 15:00-05:00 UTC, computed from FMI open
                          data magnetometer archives (CC BY 4.0) with the R method of
                          tools/alert-reference.py
  omni/omni_min<YYYYMM>.asc
                          NASA OMNI 1-minute data (OMNIWeb/SPDF, public domain)
  kp/Kp_ap_since_1932.txt GFZ Potsdam definitive Kp (CC BY 4.0: Matzka, J., Stolle, C.,
                          Yamazaki, Y., Bronkalla, O. and Morschhauser, A., 2021. The
                          geomagnetic Kp index and derived indices of geomagnetic activity.
                          Space Weather, https://doi.org/10.1029/2020SW002641)

Python 3 standard library only.
"""

from __future__ import annotations

import gzip
import importlib.util
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CACHE = REPO_ROOT / "tools/.cache"
FIXTURES = REPO_ROOT / "Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook"
STATIONS_JSON = REPO_ROOT / "Packages/AuroraCore/Sources/AuroraCore/Resources/stations.json"

WFS_URL = "https://opendata.fmi.fi/wfs"
OMNI_URL = "https://spdf.gsfc.nasa.gov/pub/data/omni/high_res_omni/monthly_1min/omni_min{:%Y%m}.asc"
KP_URL = "https://kp.gfz.de/app/files/Kp_ap_since_1932.txt"
TIMEOUT = 180

# contracts/soon-rules.md#bands
BANDS = {
    "north": ["KEV", "KIL", "IVA", "MUO", "PEL"],
    "central": ["RAN", "OUJ", "MEK", "HAN"],
    "south": ["TAR"],
}
BAND_OF = {code: band for band, codes in BANDS.items() for code in codes}

# A night is 15:00 UTC on the evening's date to 05:00 UTC the next morning, as the recorded alert
# nights of spec 002.
NIGHT_START_HOUR = 15
NIGHT_HOURS = 14
LEAD_IN = timedelta(minutes=10)

MEMBER_RE = re.compile(r"<wfs:member>.*?</wfs:member>", re.S)
POS_RE = re.compile(r"<gml:pos>\s*([-0-9.]+)\s+([-0-9.]+)\s*</gml:pos>")
TIME_RE = re.compile(r"<BsWfs:Time>([^<]+)</BsWfs:Time>")
PARAM_RE = re.compile(r"<BsWfs:ParameterName>([^<]+)</BsWfs:ParameterName>")
VALUE_RE = re.compile(r"<BsWfs:ParameterValue>([^<]*)</BsWfs:ParameterValue>")


def _load_reference():
    """tools/alert-reference.py: the independent R, sun and chance implementation."""
    spec = importlib.util.spec_from_file_location("alert_reference", REPO_ROOT / "tools/alert-reference.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reference = _load_reference()
STATIONS = {s["id"]: s for s in json.loads(STATIONS_JSON.read_text())}


def iso(t: datetime) -> str:
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_utc(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)


def night_window(evening: date) -> tuple[datetime, datetime]:
    start = datetime(evening.year, evening.month, evening.day, NIGHT_START_HOUR, tzinfo=timezone.utc)
    return start, start + timedelta(hours=NIGHT_HOURS)


def fetch(url: str, retries: int = 3) -> bytes:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={
                "Accept-Encoding": "gzip",
                "User-Agent": "revontulet-calibration/1.0 (development tool)",
            })
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                body = resp.read()
                enc = (resp.headers.get("Content-Encoding") or "").lower()
            if enc == "gzip" or body[:2] == b"\x1f\x8b":
                body = gzip.decompress(body)
            elif enc == "deflate":
                body = zlib.decompress(body)
            return body
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt == retries - 1:
                raise
            print(f"  retry after {e}", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    raise AssertionError


# ---------------------------------------------------------------- activity (FMI)

def activity(r: float | None, code: str) -> str | None:
    if r is None:
        return None
    station = STATIONS[code]
    if r >= station["redThreshold"]:
        return "probable"
    if r >= station["yellowThreshold"]:
        return "possible"
    return "unlikely"


ACTIVITY_RANK = {"unlikely": 0, "possible": 1, "probable": 2}

# The archive has single-sample glitches (R up to 65,842 on 2024-09-05, even at Tartu). One bad
# 10 s sample lifts R for exactly the 10 minutes its window covers, so a level counts only when it
# holds for at least this many consecutive minutes.
SUSTAINED_MINUTES = 15


def sustained_runs(series: list[tuple[int, float | None]], code: str, level: str) -> list[int]:
    """Start minutes (epoch) of runs of at least SUSTAINED_MINUTES consecutive minutes at
    `level` or above. `series` is [(minute epoch, R)] sorted by time."""
    starts, run_start, run_length, last = [], None, 0, None
    for minute, r in series:
        at_level = (a := activity(r, code)) is not None and ACTIVITY_RANK[a] >= ACTIVITY_RANK[level]
        if at_level and last is not None and minute - last == 60 and run_start is not None:
            run_length += 1
        elif at_level:
            run_start, run_length = minute, 1
        else:
            run_start, run_length = None, 0
        last = minute
        if run_length == SUSTAINED_MINUTES:
            starts.append(run_start)
    return starts


def sustained_level(series: list[tuple[int, float | None]], code: str) -> str:
    """The highest activity level held for at least SUSTAINED_MINUTES consecutive minutes."""
    for level in ("probable", "possible"):
        if sustained_runs(series, code, level):
            return level
    return "unlikely"


def _station_for(lat: float, lon: float) -> str | None:
    for code, s in STATIONS.items():
        if abs(lat - s["latitude"]) <= 0.01 and abs(lon - s["longitude"]) <= 0.01:
            return code
    return None


def night_r(evening: date) -> dict[str, dict[int, float | None]]:
    """R per station at every minute of the night: {code: {epoch: r or None}}. Cached."""
    path = CACHE / "nights" / f"{evening:%Y%m%d}.json"
    if path.exists():
        data = json.loads(path.read_text())
        return {code: {int(t): r for t, r in rows} for code, rows in data["stations"].items()}

    start, end = night_window(evening)
    samples: dict[str, dict[int, tuple[float, float, float]]] = {c: {} for c in STATIONS}
    partial: dict[str, dict[int, dict[str, float]]] = {c: {} for c in STATIONS}
    chunk = start - LEAD_IN
    print(f"  FMI magnetometer {evening} ", end="", file=sys.stderr, flush=True)
    while chunk < end:
        chunk_end = min(chunk + timedelta(hours=1) - timedelta(seconds=10), end)
        query = {
            "service": "WFS", "version": "2.0.0", "request": "getFeature",
            "storedquery_id": "fmi::observations::magnetometer::simple", "bbox": "5,50,40,80",
            "parameters": "MAGNX_PT10S_AVG,MAGNY_PT10S_AVG,MAGNZ_PT10S_AVG",
            "starttime": iso(chunk), "endtime": iso(chunk_end),
        }
        text = fetch(WFS_URL + "?" + urllib.parse.urlencode(query, safe=":,")).decode("utf-8")
        for m in MEMBER_RE.finditer(text):
            block = m.group(0)
            pm, tm, pa, va = POS_RE.search(block), TIME_RE.search(block), PARAM_RE.search(block), VALUE_RE.search(block)
            if not (pm and tm and pa and va):
                continue
            code = _station_for(float(pm.group(1)), float(pm.group(2)))
            value = va.group(1).strip()
            if code is None or value.lower() == "nan" or not value:
                continue
            t = int(parse_utc(tm.group(1).strip()).timestamp())
            partial[code].setdefault(t, {})[pa.group(1).strip()] = float(value)
        chunk = chunk_end + timedelta(seconds=10)
        print(".", end="", file=sys.stderr, flush=True)
    print("", file=sys.stderr)

    for code, rows in partial.items():
        for t, v in rows.items():
            if len(v) == 3:
                samples[code][t] = (v["MAGNX_PT10S_AVG"], v["MAGNY_PT10S_AVG"], v["MAGNZ_PT10S_AVG"])

    result: dict[str, dict[int, float | None]] = {}
    for code in STATIONS:
        rows = {}
        for minute in range(int(start.timestamp()), int(end.timestamp()) + 1, 60):
            r = reference.r_index(samples[code], minute) if samples[code] else None
            rows[minute] = None if r is None else round(r, 1)
        result[code] = rows
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"start": iso(start), "end": iso(end),
                                "stations": {c: sorted(rows.items()) for c, rows in result.items()}}))
    return result


def darkness_at(code: str, t: datetime) -> str:
    s = STATIONS[code]
    return reference.darkness(reference.sun_elevation(s["latitude"], s["longitude"], t))


# ---------------------------------------------------------------- Kp (GFZ)

def gfz_kp() -> dict[datetime, float]:
    """Definitive (or nowcast) Kp per 3-hour block start (UTC)."""
    path = CACHE / "kp" / "Kp_ap_since_1932.txt"
    if not path.exists() or time.time() - path.stat().st_mtime > 86_400:
        path.parent.mkdir(parents=True, exist_ok=True)
        print("  GET GFZ Kp", file=sys.stderr)
        path.write_bytes(fetch(KP_URL))
    blocks = {}
    for line in path.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split()
        year, month, day, hour, kp = int(f[0]), int(f[1]), int(f[2]), float(f[3]), float(f[7])
        if year < 2024 or kp < 0:
            continue
        blocks[datetime(year, month, day, int(hour), tzinfo=timezone.utc)] = kp
    return blocks


def max_kp(blocks: dict[datetime, float], start: datetime, end: datetime) -> float | None:
    """Highest Kp of the 3-hour blocks overlapping [start, end)."""
    values = [kp for t, kp in blocks.items() if t < end and t + timedelta(hours=3) > start]
    return max(values) if values else None


# ---------------------------------------------------------------- solar wind (OMNI)

def _omni_month(month: date) -> Path:
    path = CACHE / "omni" / f"omni_min{month:%Y%m}.asc"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        print(f"  GET OMNI {month:%Y-%m}", file=sys.stderr)
        path.write_bytes(fetch(OMNI_URL.format(month)))
    return path


_omni_rows: dict[str, list[tuple]] = {}
SHIFT_WINDOW = 30  # minutes either side for the running median of OMNI's timeshift


def _omni_parsed(month: date) -> list[tuple]:
    """(bow shock time, timeshift s or None, Bz GSM, speed, density) per OMNI minute."""
    key = f"{month:%Y%m}"
    if key not in _omni_rows:
        parsed = []
        for line in _omni_month(month).read_text().splitlines():
            f = line.split()
            if len(f) < 26:
                continue
            t = datetime(int(f[0]), 1, 1, int(f[2]), int(f[3]), tzinfo=timezone.utc) + timedelta(days=int(f[1]) - 1)
            shift, bz, speed, density = int(f[9]), float(f[18]), float(f[21]), float(f[25])
            parsed.append((t, None if shift >= 999_999 else shift, None if bz >= 9999 else bz,
                           None if speed >= 99999 else speed, None if density >= 999 else density))
        _omni_rows[key] = parsed
    return _omni_rows[key]


def omni(start: datetime, end: datetime) -> list[tuple[datetime, datetime, float | None, float | None, float | None]]:
    """Solar wind as SWPC's propagated product would have given it: one row per minute observed
    at L1, as (L1 time, arrival at the bow shock, Bz GSM, speed, density), sorted by L1 time.

    OMNI rows are time-shifted to the bow shock nose. Its per-minute timeshift is noisy (it
    follows each minute's phase front), so the L1 time is the row time minus the running median
    of the timeshift over an hour. Fill values become None.
    """
    rows = []
    month = date(start.year, start.month, 1)
    last = (end + timedelta(hours=3)).date()
    while month <= last:
        rows += [r for r in _omni_parsed(month) if start <= r[0] <= end + timedelta(hours=3)]
        month = date(month.year + (month.month == 12), month.month % 12 + 1, 1)
    rows.sort(key=lambda r: r[0])

    by_minute = {}
    for i, (t, _, bz, speed, density) in enumerate(rows):
        shifts = sorted(r[1] for r in rows[max(0, i - SHIFT_WINDOW): i + SHIFT_WINDOW + 1] if r[1] is not None)
        if not shifts:
            continue
        observed = (t - timedelta(seconds=shifts[len(shifts) // 2])).replace(second=0, microsecond=0)
        if start <= observed <= end:
            by_minute[observed] = [observed, t, bz, speed, density]
    result = [by_minute[m] for m in sorted(by_minute)]
    for column in (3, 4):
        _fill_gaps(result, column)
    return [tuple(r) for r in result]


PLASMA_GAP = timedelta(minutes=60)


def _fill_gaps(rows: list[list], column: int) -> None:
    """OMNI's 1-minute plasma (speed, density) has many short gaps where the field is present.
    Both change slowly, so gaps of up to an hour are filled by linear interpolation for the
    replay. Bz is never filled."""
    known = [i for i, r in enumerate(rows) if r[column] is not None]
    for a, b in zip(known, known[1:]):
        if b - a < 2 or rows[b][0] - rows[a][0] > PLASMA_GAP:
            continue
        span = (rows[b][0] - rows[a][0]).total_seconds()
        for i in range(a + 1, b):
            share = (rows[i][0] - rows[a][0]).total_seconds() / span
            rows[i][column] = round(rows[a][column] + share * (rows[b][column] - rows[a][column]), 2)


# ---------------------------------------------------------------- soon rule (contracts/soon-rules.md)

SOON_RANK = {"quiet": 0, "possible": 1, "likely": 2}
LATENCY = timedelta(minutes=8)  # the propagated product runs about 8 minutes behind


def soon_driver(samples, now: datetime) -> float | None:
    """Soon-rules steps 1-4, an independent implementation: the median Ey, or None (Unknown)."""
    valid = [s for s in samples if s[2] is not None and s[3] is not None and s[0] <= now]
    if not valid:
        return None
    newest = valid[-1][0]
    if now - newest > timedelta(minutes=20):
        return None
    window = [s for s in valid if newest - timedelta(minutes=19) <= s[0] <= newest]
    if len(window) < 15:
        return None
    ey = sorted(s[3] * max(0.0, -s[2]) / 1000 for s in window)
    n = len(ey)
    return ey[n // 2] if n % 2 else (ey[n // 2 - 1] + ey[n // 2]) / 2


def soon_classify(driver: float | None, possible: float, likely: float, previous: str | None) -> str:
    """Soon-rules steps 5-6."""
    if driver is None:
        return "unknown"
    state = "likely" if driver >= likely else "possible" if driver >= possible else "quiet"
    thresholds = {"possible": possible, "likely": likely}
    if previous in thresholds and SOON_RANK[previous] > SOON_RANK[state] and driver >= 0.75 * thresholds[previous]:
        state = previous
    return state
