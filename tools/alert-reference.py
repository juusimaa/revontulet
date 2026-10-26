#!/usr/bin/env python3
"""Expected alerts for a recorded alert night (specs/002-aurora-alerts T016).

DEVELOPMENT TOOL ONLY. An independent implementation of the rules in
specs/002-aurora-alerts/contracts/alert-rules.md and
specs/001-aurora-main-screen/contracts/chance-rules.md, used to write the
expected.json that the Swift ZoneEvaluator/AlertPolicy/EvaluationLoop tests
compare against, so the expected alerts do not come from the code under test.

Replays the night in 5-minute evaluation cycles from night.json's start to its
end, fetching the way the service does: magnetometer every cycle (12 minutes back),
clouds every 10 minutes (30 minutes back).

Writes into the night folder:
  expected.json  [{"zone", "level", "time"}] -- alerts in cycle order
And prints a review summary: per zone the highest R, activity and chance, every
alert with its reason, and (when reference-r.json exists) how this R compares
with FMI's published R.

Usage:
  python3 tools/alert-reference.py Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/alerts/20261024
"""

from __future__ import annotations

import csv
import json
import math
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

HELSINKI = ZoneInfo("Europe/Helsinki")
REPO_ROOT = Path(__file__).resolve().parent.parent
STATIONS_JSON = REPO_ROOT / "Packages/AuroraCore/Sources/AuroraCore/Resources/stations.json"

CYCLE = timedelta(minutes=5)
CLOUDS_INTERVAL = timedelta(minutes=10)
LEVELS = ["none", "low", "moderate", "high"]


def parse_utc(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)


def iso(t: datetime) -> str:
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def epoch(t: datetime) -> int:
    return int(t.timestamp())


# ---------------------------------------------------------------- geometry

def distance_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat, dlon = lat2 - lat1, math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * 6371.0 * math.asin(min(1.0, math.sqrt(h)))


# ---------------------------------------------------------------- R (FMI, research R1 of 001)

def r_index(samples: dict[int, tuple[float, float, float]], end: int) -> float | None:
    """10 minutes ending at `end`: 61 samples end-610 .. end-10, newest half weighted 2."""
    window = [samples.get(end - k * 10) for k in range(1, 62)]
    if sum(1 for w in window if w is None) > 3:
        return None
    num = den = 0.0
    for k in range(60):
        a, b = window[k], window[k + 1]
        if a is None or b is None:
            continue
        w = 2.0 if k < 30 else 1.0
        num += w * sum(abs(a[i] - b[i]) for i in range(3))
        den += w
    if den == 0:
        return None
    return max(0.0, 45.0 * num / den - 1.5)


# ---------------------------------------------------------------- sun (NOAA)

def sun_elevation(lat: float, lon: float, t: datetime) -> float:
    s = t.timestamp()
    jd = s / 86400 + 2440587.5
    jc = (jd - 2451545) / 36525
    l0 = math.fmod(280.46646 + jc * (36000.76983 + jc * 0.0003032), 360)
    m = 357.52911 + jc * (35999.05029 - 0.0001537 * jc)
    e = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
    c = (math.sin(math.radians(m)) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
         + math.sin(math.radians(2 * m)) * (0.019993 - 0.000101 * jc)
         + math.sin(math.radians(3 * m)) * 0.000289)
    omega = 125.04 - 1934.136 * jc
    app_long = l0 + c - 0.00569 - 0.00478 * math.sin(math.radians(omega))
    mean_obl = 23 + (26 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60) / 60
    obl = mean_obl + 0.00256 * math.cos(math.radians(omega))
    decl = math.asin(math.sin(math.radians(obl)) * math.sin(math.radians(app_long)))
    y = math.tan(math.radians(obl / 2)) ** 2
    rl0, rm = math.radians(l0), math.radians(m)
    eot = 4 * math.degrees(y * math.sin(2 * rl0) - 2 * e * math.sin(rm)
                           + 4 * e * y * math.sin(rm) * math.cos(2 * rl0)
                           - 0.5 * y * y * math.sin(4 * rl0) - 1.25 * e * e * math.sin(2 * rm))
    utc_min = math.fmod(s, 86400) / 60
    tst = math.fmod(utc_min + eot + 4 * lon, 1440)
    if tst < 0:
        tst += 1440
    ha = math.radians(tst / 4 - 180)
    rlat = math.radians(lat)
    cz = math.sin(rlat) * math.sin(decl) + math.cos(rlat) * math.cos(decl) * math.cos(ha)
    return 90 - math.degrees(math.acos(min(1.0, max(-1.0, cz))))


def darkness(elevation: float) -> str:
    if elevation > -6:
        return "tooLight"
    if elevation > -12:
        return "twilight"
    return "dark"


# ---------------------------------------------------------------- chance (001 chance-rules.md)

def cloud_condition(octas: int | None) -> str:
    if octas is None:
        return "unknown"
    if octas <= 3:
        return "clear"
    if octas <= 6:
        return "partly"
    if octas <= 8:
        return "overcast"
    return "unknown"


def chance(activity: str, dark: str, clouds: str) -> tuple[str, str | None]:
    """(level, limiting factor)."""
    if dark == "tooLight":
        return "none", "light"
    if clouds == "overcast":
        return "none", "clouds"
    level = {"unlikely": 1, "possible": 2, "probable": 3}[activity]
    limit = None
    if dark == "twilight":
        level, limit = max(0, level - 1), "twilight"
    if clouds == "partly":
        level, limit = max(0, level - 1), "clouds"
    if limit is None and level != 3:
        limit = "activity"
    return LEVELS[level], limit


def reason(limit: str | None, activity: str, clouds: str) -> str:
    if limit == "light":
        return "tooLight"
    if limit == "clouds":
        return "overcast" if clouds == "overcast" else "partlyCloudy"
    if limit == "twilight":
        return "twilight"
    if limit == "activity":
        return "lowActivity" if activity == "unlikely" else "someActivity"
    return "goodConditions"


# ---------------------------------------------------------------- data

def load_magnetometer(folder: Path) -> dict[str, dict[int, tuple[float, float, float]]]:
    """Complete samples per station: {code: {epoch second: (x, y, z)}}."""
    result = {}
    for path in folder.glob("magnetometer-*.csv"):
        code = path.stem.split("-")[1]
        samples = {}
        for line in path.read_text().splitlines():
            if line.startswith("#") or line.startswith("time"):
                continue
            t, x, y, z = line.split(",")
            if x and y and z:
                samples[epoch(parse_utc(t))] = (float(x), float(y), float(z))
        result[code] = samples
    return result


def load_clouds(folder: Path) -> list[tuple[int, tuple[float, float], float | None]]:
    rows = []
    with (folder / "clouds.csv").open() as f:
        for row in csv.reader(line for line in f if not line.startswith("#")):
            if row[0] == "time":
                continue
            value = float(row[3]) if row[3] else None
            rows.append((epoch(parse_utc(row[0])), (float(row[1]), float(row[2])), value))
    return rows


def latest_clouds(rows, fetched_at: int) -> dict[tuple[float, float], int | None]:
    """Latest value per position in [fetched_at - 30 min, fetched_at]; octas 0..8 else None."""
    latest: dict[tuple[float, float], tuple[int, float | None]] = {}
    for t, pos, value in rows:
        if fetched_at - 1800 <= t <= fetched_at and (pos not in latest or latest[pos][0] < t):
            latest[pos] = (t, value)
    return {pos: (round(v) if v is not None and 0 <= v <= 8 else None) for pos, (_, v) in latest.items()}


# ---------------------------------------------------------------- alert rules (alert-rules.md §2)

def night_key(t: datetime) -> str:
    return (t - timedelta(hours=12)).astimezone(HELSINKI).date().isoformat()


def decide(level: str, data_time: datetime, now: datetime, state: dict) -> str | None:
    c = LEVELS.index(level)
    key = night_key(now)
    if key != state["night"]:
        state["night"], state["alertsTonight"] = key, 0
    for name in ("moderate", "high"):
        lv = LEVELS.index(name)
        if name in state["alerted"]:
            if c < lv:
                since = state["belowSince"].setdefault(name, now)
                if now - since >= timedelta(minutes=60):
                    state["alerted"].discard(name)
                    del state["belowSince"][name]
            else:
                state["belowSince"].pop(name, None)
    candidate = next((n for n in ("high", "moderate") if c >= LEVELS.index(n) and n not in state["alerted"]), None)
    if candidate is None:
        return None
    if now - data_time > timedelta(minutes=20):
        return None
    marked = {"moderate"} if candidate == "moderate" else {"moderate", "high"}
    if state["alertsTonight"] >= 3:
        state["alerted"] |= marked
        return None
    state["alerted"] |= marked
    state["alertsTonight"] += 1
    return candidate


# ---------------------------------------------------------------- replay

def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    folder = Path(sys.argv[1])
    night = json.loads((folder / "night.json").read_text())
    start, end = parse_utc(night["start"]), parse_utc(night["end"])
    stations = json.loads(STATIONS_JSON.read_text())
    position = {s["id"]: (s["latitude"], s["longitude"]) for s in stations}
    magnetometer = load_magnetometer(folder)
    cloud_rows = load_clouds(folder)

    states = {s["id"]: {"night": "", "alertsTonight": 0, "alerted": set(), "belowSince": {}} for s in stations}
    summary = {s["id"]: {"maxR": 0.0, "maxActivity": "unlikely", "maxChance": "none"} for s in stations}
    alerts = []
    clouds_fetched_at = None
    clouds: dict = {}

    t = start
    while t <= end:
        now = epoch(t)
        if clouds_fetched_at is None or now - clouds_fetched_at >= CLOUDS_INTERVAL.total_seconds():
            clouds_fetched_at = now
            clouds = latest_clouds(cloud_rows, now)

        # Readings: the magnetometer request covers floor10(now - 12 min) .. now.
        request_start = (now - 720) // 10 * 10
        readings = {}
        for s in stations:
            samples = {k: v for k, v in magnetometer.get(s["id"], {}).items() if request_start <= k <= now}
            if not samples:
                readings[s["id"]] = None
                continue
            r_end = max(samples) + 10
            r = r_index(samples, r_end)
            if r is None:
                readings[s["id"]] = None
                continue
            activity = "probable" if r >= s["redThreshold"] else "possible" if r >= s["yellowThreshold"] else "unlikely"
            readings[s["id"]] = (r, activity, r_end)

        for s in stations:
            zone = s["id"]
            pos = position[zone]
            valid = sorted((distance_km(pos, position[c]), c) for c, rd in readings.items() if rd is not None)
            if not valid:
                continue
            r, activity, r_end = readings[valid[0][1]]
            dark = darkness(sun_elevation(pos[0], pos[1], t))
            near = [(distance_km(pos, p), o) for p, o in clouds.items() if o is not None]
            near = [x for x in near if x[0] <= 100]
            cloud = cloud_condition(min(near)[1]) if near else "unknown"
            level, limit = chance(activity, dark, cloud)

            info = summary[zone]
            if valid[0][1] == zone:
                info["maxR"] = max(info["maxR"], r)
                if ["unlikely", "possible", "probable"].index(activity) > ["unlikely", "possible", "probable"].index(info["maxActivity"]):
                    info["maxActivity"] = activity
            if LEVELS.index(level) > LEVELS.index(info["maxChance"]):
                info["maxChance"] = level

            decided = decide(level, datetime.fromtimestamp(r_end, timezone.utc), t, states[zone])
            if decided:
                alerts.append({"zone": zone, "level": decided, "time": iso(t)})
                why = reason(limit, activity, cloud)
                print(f"ALERT {iso(t)} ({t.astimezone(HELSINKI):%H:%M} local) {zone} {decided:8s} "
                      f"R={r:.1f} via {valid[0][1]} {activity} {dark} clouds={cloud} -> {why}")
        t += CYCLE

    (folder / "expected.json").write_text(json.dumps(alerts, indent=1) + "\n")

    print(f"\n{folder.name}: {len(alerts)} alerts, night {iso(start)} .. {iso(end)}")
    print("zone  maxR    maxActivity  maxChance")
    for zone, info in summary.items():
        print(f"{zone}  {info['maxR']:6.1f}  {info['maxActivity']:11s}  {info['maxChance']}")

    reference = folder / "reference-r.json"
    if reference.exists():
        diffs = []
        thresholds = {s["id"]: (s["yellowThreshold"], s["redThreshold"]) for s in stations}
        levels_compared = levels_differ = 0
        for row in json.loads(reference.read_text()):
            mine = r_index(magnetometer.get(row["station"], {}), epoch(parse_utc(row["time"])))
            if mine is not None and row["r"] is not None:
                yellow, red = thresholds[row["station"]]
                level = lambda r: 2 if r >= red else 1 if r >= yellow else 0  # noqa: E731
                levels_compared += 1
                if level(mine) != level(row["r"]):
                    levels_differ += 1
                    print(f"  activity differs: {row['station']} {row['time']} R {mine:.1f} vs FMI {row['r']:.1f}")
            if mine is not None and row["r"]:
                diffs.append((abs(mine - row["r"]) / max(row["r"], 1.0), row["station"], row["time"], mine, row["r"]))
        print(f"\nActivity level vs FMI reference: {levels_compared - levels_differ}/{levels_compared} agree")
        if diffs:
            diffs.sort()
            median = diffs[len(diffs) // 2][0]
            print(f"\nR vs FMI reference: {len(diffs)} points compared, median relative difference "
                  f"{median:.1%}, worst {diffs[-1][0]:.1%} ({diffs[-1][1]} {diffs[-1][2]}: "
                  f"{diffs[-1][3]:.1f} vs {diffs[-1][4]:.1f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
