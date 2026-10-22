#!/usr/bin/env python3
"""Build the bundled Finnish municipality boundary resource for AuroraCore.

Downloads Statistics Finland's 1:1 000 000 municipality boundaries (2026) as
GeoJSON, rounds coordinates to 4 decimals, simplifies every ring with
Douglas-Peucker and writes compact JSON to
Packages/AuroraCore/Sources/AuroraCore/Resources/municipalities.json.

Usage:
    python3 tools/build-municipalities.py               # download (cached) and build
    python3 tools/build-municipalities.py --input F     # build from a local GeoJSON file
    python3 tools/build-municipalities.py --refresh     # ignore the download cache
    python3 tools/build-municipalities.py --tolerance T # simplification tolerance in degrees
    python3 tools/build-municipalities.py --self-test   # check known points against the output

Output schema (all coordinates are [lat, lon] in WGS84 degrees, 4 decimals):
    {
      "source": "<WFS URL>",
      "licence": "CC BY 4.0",
      "attribution": "Municipality boundaries: Statistics Finland, CC BY 4.0",
      "year": 2026,
      "municipalities": [            # sorted by code
        {
          "code": "091",             # 3-digit municipality code (kunta)
          "nameFi": "Helsinki",      # Finnish name (nimi)
          "nameSv": "Helsingfors",   # Swedish name (namn); null if empty or same as nameFi
          "point": [lat, lon],       # representative point inside the municipality
          "bbox": [minLat, minLon, maxLat, maxLon],
          "polygons": [              # one entry per polygon part (islands etc.)
            {"outer": [[lat, lon], ...],          # outer ring
             "holes": [[[lat, lon], ...], ...]}   # inner rings (usually empty)
          ]
        }
      ]
    }
Rings are implicitly closed: the closing point (equal to the first) is omitted.
A point is inside a municipality if, for some polygon, it is inside `outer`
and not inside any of its `holes` (even-odd ray casting).

Data notes:
- The WFS returns GeoJSON in [lon, lat] order despite the EPSG:4326 URN; the
  order is detected from the coordinate ranges (Finland: lat 59-71, lon 19-32)
  and normalised, so either order is accepted.
- `nimi` is kept as given except when it holds both names separated by " - "
  (e.g. "Maarianhamina - Mariehamn"); then the Finnish part is used for nameFi.
- Simplification: Douglas-Peucker per ring, after rounding, in the plane
  x = lon * cos(lat0), y = lat (lat0 = municipality's mid-latitude), so the
  tolerance (default 0.0003 deg, ~30 m) is isotropic. A ring is never reduced
  below 4 points; rings are only dropped when tiny after rounding (< 3 points).
- The representative point is the pole of inaccessibility (polylabel) of the
  largest polygon part, computed in an equirectangular projection scaled by
  cos(lat) so that it is not biased in longitude.
"""

import argparse
import heapq
import json
import math
import sys
import urllib.request
from pathlib import Path

YEAR = 2026
SOURCE_URL = (
    "https://geo.stat.fi/geoserver/tilastointialueet/wfs?service=WFS&version=2.0.0"
    f"&request=GetFeature&typeName=tilastointialueet:kunta1000k_{YEAR}"
    "&outputFormat=application/json&srsName=EPSG:4326"
)
EXPECTED_COUNT = 308
DECIMALS = 4
DEFAULT_TOLERANCE = 0.0003  # degrees of latitude (~30 m)
MIN_RING_POINTS = 4
POLYLABEL_PRECISION = 0.0005  # degrees (of latitude, in the scaled projection)

REPO_ROOT = Path(__file__).resolve().parent.parent
CACHE_FILE = REPO_ROOT / "tools" / ".cache" / f"kunta1000k_{YEAR}.geojson"
OUTPUT_FILE = (
    REPO_ROOT / "Packages" / "AuroraCore" / "Sources" / "AuroraCore" / "Resources" / "municipalities.json"
)

SELF_TEST_POINTS = [
    # (label, lat, lon, expected code or None)
    ("Helsinki centre", 60.1699, 24.9384, "091"),
    ("Suomenlinna", 60.146, 24.988, "091"),
    ("Tornio centre", 65.846, 24.146, "851"),
    ("Stockholm", 59.33, 18.07, None),
]


# --- input ------------------------------------------------------------------

def load_geojson(input_path, refresh):
    if input_path:
        return json.loads(Path(input_path).read_text(encoding="utf-8"))
    if refresh or not CACHE_FILE.exists():
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {SOURCE_URL}")
        with urllib.request.urlopen(SOURCE_URL, timeout=120) as response:
            CACHE_FILE.write_bytes(response.read())
    else:
        print(f"Using cached {CACHE_FILE.relative_to(REPO_ROOT)}")
    return json.loads(CACHE_FILE.read_text(encoding="utf-8"))


def detect_lon_lat_order(features):
    """True if positions are [lon, lat]; Finland's lat and lon ranges don't overlap."""
    first, second = [], []
    for feature in features:
        for polygon in polygons_of(feature["geometry"]):
            for x, y in polygon[0][:1]:
                first.append(x)
                second.append(y)
    mean_first = sum(first) / len(first)
    mean_second = sum(second) / len(second)
    if 19 <= mean_first <= 32 and 59 <= mean_second <= 71:
        return True
    if 59 <= mean_first <= 71 and 19 <= mean_second <= 32:
        return False
    sys.exit(f"Cannot determine axis order (means {mean_first:.2f}, {mean_second:.2f})")


def polygons_of(geometry):
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    sys.exit(f"Unexpected geometry type {geometry['type']}")


# --- geometry -----------------------------------------------------------------

def clean_ring(ring, lon_lat):
    """Round to [lat, lon], drop consecutive duplicates and the closing point."""
    out = []
    for position in ring:
        a, b = position[0], position[1]
        lat, lon = (b, a) if lon_lat else (a, b)
        point = [round(lat, DECIMALS), round(lon, DECIMALS)]
        if not out or out[-1] != point:
            out.append(point)
    while len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out if len(out) >= 3 else None


def simplify_ring(ring, tolerance, kx):
    """Douglas-Peucker for a closed ring of [lat, lon] in the cos(lat)-scaled plane.

    Keeps at least MIN_RING_POINTS points (or all of them if the ring is smaller),
    halving the tolerance until that holds.
    """
    if len(ring) <= MIN_RING_POINTS or tolerance <= 0:
        return ring
    xy = [(lon * kx, lat) for lat, lon in ring] + [(ring[0][1] * kx, ring[0][0])]
    # Split the closed ring at the vertex farthest from the first one.
    far = max(range(len(ring)), key=lambda i: (xy[i][0] - xy[0][0]) ** 2 + (xy[i][1] - xy[0][1]) ** 2)
    while tolerance > 1e-9:
        keep = {0, far}
        tol_sq = tolerance * tolerance
        stack = [(0, far), (far, len(ring))]
        while stack:
            first, last = stack.pop()
            ax, ay = xy[first]
            bx, by = xy[last]
            best_sq, best_i = -1.0, None
            for i in range(first + 1, last):
                d = segment_distance_sq(xy[i][0], xy[i][1], ax, ay, bx, by)
                if d > best_sq:
                    best_sq, best_i = d, i
            if best_i is not None and best_sq > tol_sq:
                keep.add(best_i)
                stack += [(first, best_i), (best_i, last)]
        if len(keep) >= MIN_RING_POINTS:
            return [ring[i] for i in sorted(keep)]
        tolerance /= 2
    return ring


def ring_area(ring, kx):
    """Absolute shoelace area in the scaled projection (x = lon * kx, y = lat)."""
    s = 0.0
    for i in range(len(ring)):
        (y1, x1), (y2, x2) = ring[i - 1], ring[i]
        s += (x1 * kx) * y2 - (x2 * kx) * y1
    return abs(s) / 2


def point_in_ring(lat, lon, ring):
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        yi, xi = ring[i]
        yj, xj = ring[j]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def point_in_polygon(lat, lon, polygon):
    return point_in_ring(lat, lon, polygon["outer"]) and not any(
        point_in_ring(lat, lon, hole) for hole in polygon["holes"]
    )


def point_in_municipality(lat, lon, municipality):
    min_lat, min_lon, max_lat, max_lon = municipality["bbox"]
    if not (min_lat <= lat <= max_lat and min_lon <= lon <= max_lon):
        return False
    return any(point_in_polygon(lat, lon, p) for p in municipality["polygons"])


def polylabel(polygon, precision):
    """Pole of inaccessibility (Mapbox polylabel) for one polygon with holes.

    Works in a local projection x = lon * cos(lat0), y = lat so distances are
    isotropic; returns [lat, lon].
    """
    rings = [polygon["outer"], *polygon["holes"]]
    lats = [p[0] for p in polygon["outer"]]
    lat0 = (min(lats) + max(lats)) / 2
    kx = math.cos(math.radians(lat0))
    proj = [[(lon * kx, lat) for lat, lon in ring] for ring in rings]

    def signed_distance(x, y):
        inside = False
        min_sq = math.inf
        for ring in proj:
            j = len(ring) - 1
            for i in range(len(ring)):
                ax, ay = ring[i]
                bx, by = ring[j]
                if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
                    inside = not inside
                min_sq = min(min_sq, segment_distance_sq(x, y, ax, ay, bx, by))
                j = i
        d = math.sqrt(min_sq)
        return d if inside else -d

    xs = [p[0] for p in proj[0]]
    ys = [p[1] for p in proj[0]]
    min_x, min_y, max_x, max_y = min(xs), min(ys), max(xs), max(ys)
    cell_size = min(max_x - min_x, max_y - min_y)
    if cell_size == 0:
        return [min_y, min_x / kx]

    def cell(x, y, h):
        d = signed_distance(x, y)
        return (-(d + h * math.sqrt(2)), d, x, y, h)  # heap key = -max possible

    heap = []
    h = cell_size / 2
    y = min_y
    while y < max_y:
        x = min_x
        while x < max_x:
            heapq.heappush(heap, cell(x + h, y + h, h))
            x += cell_size
        y += cell_size

    # Seed with the centroid of the outer ring and the bbox centre.
    cx, cy = centroid(proj[0])
    best = cell(cx, cy, 0)
    bbox_cell = cell((min_x + max_x) / 2, (min_y + max_y) / 2, 0)
    if bbox_cell[1] > best[1]:
        best = bbox_cell

    while heap:
        c = heapq.heappop(heap)
        _, d, x, y, h = c
        if d > best[1]:
            best = c
        if -c[0] - best[1] <= precision:
            continue
        h /= 2
        for dx in (-h, h):
            for dy in (-h, h):
                heapq.heappush(heap, cell(x + dx, y + dy, h))

    _, _, x, y, _ = best
    return [y, x / kx]


def segment_distance_sq(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    if dx or dy:
        t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
        if t > 1:
            ax, ay = bx, by
        elif t > 0:
            ax += dx * t
            ay += dy * t
    return (px - ax) ** 2 + (py - ay) ** 2


def centroid(ring):
    area = cx = cy = 0.0
    for i in range(len(ring)):
        ax, ay = ring[i - 1]
        bx, by = ring[i]
        f = ax * by - bx * ay
        cx += (ax + bx) * f
        cy += (ay + by) * f
        area += f * 3
    if area == 0:
        return ring[0]
    return cx / area, cy / area


# --- build --------------------------------------------------------------------

def split_names(props):
    name_fi = props["nimi"].strip()
    name_sv = (props.get("namn") or "").strip()
    if " - " in name_fi:
        fi_part, sv_part = (s.strip() for s in name_fi.split(" - ", 1))
        if not name_sv or sv_part == name_sv:
            name_fi, name_sv = fi_part, name_sv or sv_part
    return name_fi, (name_sv if name_sv and name_sv != name_fi else None)


def build_municipality(feature, lon_lat, tolerance):
    props = feature["properties"]
    name_fi, name_sv = split_names(props)

    polygons = []
    for rings in polygons_of(feature["geometry"]):
        outer = clean_ring(rings[0], lon_lat)
        if outer is None:
            continue
        holes = [h for h in (clean_ring(r, lon_lat) for r in rings[1:]) if h is not None]
        polygons.append({"outer": outer, "holes": holes})
    if not polygons:
        sys.exit(f"{props['kunta']} {name_fi}: no polygons after cleaning")

    lats = [p[0] for poly in polygons for p in poly["outer"]]
    kx = math.cos(math.radians((min(lats) + max(lats)) / 2))
    for poly in polygons:
        poly["outer"] = simplify_ring(poly["outer"], tolerance, kx)
        poly["holes"] = [simplify_ring(h, tolerance, kx) for h in poly["holes"]]

    all_points = [p for poly in polygons for p in poly["outer"]]
    lats = [p[0] for p in all_points]
    lons = [p[1] for p in all_points]
    bbox = [min(lats), min(lons), max(lats), max(lons)]

    largest = max(
        polygons,
        key=lambda p: ring_area(p["outer"], kx) - sum(ring_area(h, kx) for h in p["holes"]),
    )
    lat, lon = polylabel(largest, POLYLABEL_PRECISION)
    point = [round(lat, DECIMALS), round(lon, DECIMALS)]

    return {
        "code": props["kunta"],
        "nameFi": name_fi,
        "nameSv": name_sv,
        "point": point,
        "bbox": bbox,
        "polygons": polygons,
    }


def build(input_path, refresh, tolerance):
    data = load_geojson(input_path, refresh)
    features = data["features"]
    lon_lat = detect_lon_lat_order(features)
    print(f"Axis order in source: {'[lon, lat]' if lon_lat else '[lat, lon]'}")

    municipalities = sorted(
        (build_municipality(f, lon_lat, tolerance) for f in features), key=lambda m: m["code"]
    )
    assert len(municipalities) == EXPECTED_COUNT, f"expected {EXPECTED_COUNT}, got {len(municipalities)}"
    assert len({m["code"] for m in municipalities}) == EXPECTED_COUNT, "duplicate codes"
    for m in municipalities:
        assert point_in_municipality(*m["point"], m), f"{m['code']} {m['nameFi']}: point outside"

    output = {
        "source": SOURCE_URL,
        "licence": "CC BY 4.0",
        "attribution": "Municipality boundaries: Statistics Finland, CC BY 4.0",
        "year": YEAR,
        "municipalities": municipalities,
    }
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(output, ensure_ascii=False, separators=(",", ":"))
    OUTPUT_FILE.write_text(text, encoding="utf-8")
    size_kb = OUTPUT_FILE.stat().st_size / 1024
    vertices = sum(
        len(p["outer"]) + sum(len(h) for h in p["holes"]) for m in municipalities for p in m["polygons"]
    )
    print(
        f"Wrote {OUTPUT_FILE.relative_to(REPO_ROOT)}: {len(municipalities)} municipalities, "
        f"{vertices} vertices, {size_kb:.1f} KB (tolerance {tolerance})"
    )


def self_test():
    municipalities = json.loads(OUTPUT_FILE.read_text(encoding="utf-8"))["municipalities"]
    failures = 0
    for label, lat, lon, expected in SELF_TEST_POINTS:
        hits = [m["code"] for m in municipalities if point_in_municipality(lat, lon, m)]
        ok = hits == ([expected] if expected else [])
        failures += not ok
        print(f"{'PASS' if ok else 'FAIL'} {label} ({lat}, {lon}): in {hits or 'none'}, expected {expected or 'none'}")
    for m in municipalities:
        if not point_in_municipality(*m["point"], m):
            failures += 1
            print(f"FAIL {m['code']} {m['nameFi']}: representative point outside")
    print("Self-test passed" if not failures else f"Self-test failed: {failures} failure(s)")
    return failures == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--input", help="use a previously downloaded GeoJSON file")
    parser.add_argument("--refresh", action="store_true", help="re-download even if cached")
    parser.add_argument(
        "--tolerance", type=float, default=DEFAULT_TOLERANCE,
        help=f"Douglas-Peucker tolerance in degrees (default {DEFAULT_TOLERANCE}; 0 disables)",
    )
    parser.add_argument("--self-test", action="store_true", help="check known points against the output")
    args = parser.parse_args()
    if args.self_test:
        sys.exit(0 if self_test() else 1)
    build(args.input, args.refresh, args.tolerance)


if __name__ == "__main__":
    main()
