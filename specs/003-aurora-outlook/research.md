# Research: Aurora Outlook

Phase 0 decisions for [plan.md](plan.md). Facts marked **verified** were checked live on
2026-10-26; raw responses were kept in the session scratchpad and are re-recorded as fixtures
by R10.

## R1. Real-time solar wind source

**Decision**: SWPC's propagated solar wind for the last hour,
`products/geospace/propagated-solar-wind-1-hour.json` ([contract](contracts/noaa-data.md)).

**Verified**:

- **Old files are gone.** The legacy `products/solar-wind/mag-*.json` and `plasma-*.json` files
  return 404. NWS Public Information Statement 26-45 (28 May 2026) ended ACE and DSCOVR support
  and moved real-time solar wind to SOLAR-1 (SWFO-L1). IMAP and ACE also appear in the feed.
- **Format**: array of arrays with a header row; ISO UTC times with `Z`; ~53 one-minute rows;
  6.3 KB raw, ~1.9 KB gzipped; updated every 2–3 minutes; newest row ~8 minutes behind real
  time.
- **Source**: values match the SWPC "active" spacecraft's rows in `json/rtsw/` exactly (SOLAR1
  today), so `bz` is GSM and SWPC's own spacecraft choice is followed with no logic in the app.
- **Arrival time**: `propagated_time_tag` is SWPC's modelled arrival at Earth; over 7 days it
  was 43–72 minutes after observation.
- **Gaps**: few (42 in 7 days); nulls only in the velocity components. Whether SWPC fills gaps
  is not documented.

**Rationale**: smallest product (2 KB vs ~230 KB for the raw 24-hour 1-minute files), already
follows the active spacecraft, and gives the arrival time directly, so the app does not need its
own speed-based estimate.

**Alternatives considered**:
- `json/rtsw/rtsw_mag_1m.json` + `rtsw_wind_1m.json`: 24 h of all spacecraft mixed, filtered by
  `active`; ~230 KB gzipped per fetch, about 2.7 MB per hour at a 5-minute cadence. Rejected for
  data use; also no arrival time. Not used as a fallback, to keep one code path; a failure
  shows "unavailable".
- `products/summary/solar-wind-*.json`: newest value only, rounded to integers. Too little to
  apply a persistence rule.
- `json/geospace/geospace_pred_est_kp_1_hour.json` (model Kp ~45 min ahead): attractive, but a
  global index that saturates slowly for substorms over Finland; kept as a possible later input.

## R2. Kp forecast

**Decision**: `products/noaa-planetary-k-index-forecast.json`.

**Verified**: array of objects `{time_tag, kp, observed, noaa_scale}` (changed from the older
array-of-arrays). 81 three-hour blocks: ~6.5 days observed, the current day estimated, and
predicted blocks to ~2.5 days ahead (on 2026-10-26 up to 2026-10-29 00 UTC), which covers
tonight and tomorrow night in Finland (UTC+2/+3). ~0.5 KB gzipped.

**Open point**: on 2026-10-26 the JSON predicted Kp 3.0 and 2.67 for 27 Oct 00–06 UT, while the
1230 UTC text forecast gave 1.67 and 1.33. The JSON appears to follow a later or different
update. The JSON is used. The implementation records both products for a few days to check
which is newer before release; if they keep diverging, the plan is revisited.

**Alternatives considered**: `text/3-day-forecast.txt` (fixed-width text, twice daily):
harder to parse, same information; kept only as a cross-check.

## R3. Geomagnetic storm watches

**Decision**: parse watch messages from `products/alerts.json` ([contract](contracts/noaa-data.md#storm-watches-from-alertsjson)).

**Verified**: 30 days of messages, ~6 KB gzipped. Watches carry
`Space Weather Message Code: WATA20` (G1) or `WATA30` (G2) (WATA50 = G3 seen in a third-party
mirror). Day lines are `Mon DD:  Gn (Label)` without a year. Each watch supersedes all earlier
ones; cancellations reuse the code and begin `CANCEL WATCH:`. No structured JSON exists for
watches. No official code table was found, so the G level is read from the day lines, not from
the code.

**Rationale**: watches are the only SWPC product that carries forecasters' judgement about
CMEs for the next days; the Kp forecast already includes it most of the time, but a watch is
what users recognise ("G2 watch").

**Alternatives considered**: `products/noaa-scales.json` gives a predicted G scale per day but
is not a watch; the Kp forecast's `noaa_scale` is filled only for observed storms.

## R4. Moon position and phase

**Decision**: implement the moon in `AuroraCore` from Meeus, *Astronomical Algorithms*
(2nd ed.):

- Geocentric ecliptic longitude, latitude and distance from chapter 47 with the largest
  periodic terms (enough for ~0.1° accuracy).
- Equatorial coordinates and the local hour angle as in the existing `SolarPosition`.
- **Topocentric correction** for the moon's parallax (up to ~0.95°, chapter 40, or the
  altitude form `alt_topo = alt_geo − asin(sin(π)·cos(alt_geo))` with π from the distance).
  Without it SC-002's 1° limit would fail near the horizon.
- Illuminated fraction from the elongation between sun and moon (chapter 48); the sun's
  apparent longitude comes from the existing solar code, which is refactored to expose it.
- Phase name from the elongation and whether the moon is waxing (eight equal sectors).

**Reference values**: JPL Horizons (US government, public domain) for at least 20 times at
Kevo, Oulujärvi and Tartu, including moonrise and moonset, polar night and new and full moon.
Recorded once by `tools/record-moon-reference.py` into a fixture; tests never call the network.

**Rationale**: no dependency, portable (Foundation maths only), deterministic and testable,
like the sun. Algorithms are published formulas; no code is copied, so the AGPL licence is
unaffected.

**Alternatives considered**: a third-party astronomy package (SwiftAA etc.): adds a dependency
and Apple-only frameworks in some; rejected. Lower-precision formulas (~1°): would fail SC-002.

## R5. FMI cloud forecast for the outlook

**Decision**: one request to `fmi::forecast::edited::weather::scandinavia::point::simple` with
`latlon` repeated for all ten zone positions, `parameters=TotalCloudCover`, `timestep=60`.

**Verified**: repeated `latlon` returns all points (three tested) in one response; 72 hourly
values per point (three days), percent; ~1.5 KB gzipped per point; `Cache-Control:
max-age=21600`.

**Rationale**: the request is identical for every user, so it reveals nothing about the user,
which is stronger than spec FR-015 required (spec amended). It reuses `BsWfsParser`.
Refetching every 3 hours keeps well inside the 6-hour cache lifetime while catching
forecasters' updates (Principle I: no faster than the data changes).

**Alternatives considered**: one point per request for the user's zone: reveals the zone and
costs a request per zone change. Grids (GRIB/NetCDF): no decoder; rejected in spec 001.

## R6. "Soon" rule and calibration

**Decision**: the median dawn–dusk electric field `Ey = V·Bs` over the last 20 minutes at L1,
with thresholds per band and hysteresis ([soon-rules.md](contracts/soon-rules.md)).

**Rationale**: Ey (or similar coupling functions such as Newell's) is the standard driver of
substorm activity; southward Bz alone ignores speed. A median over 20 minutes needs the
conditions to persist, which matches the substorm growth phase (~30–60 min) and suppresses
spikes. Density has little effect on substorm onset in a simple rule and is not reliable in the
current feed (R1 gaps in plasma), so it is shown but not used. FR-006 is amended: Bz and
speed drive the rule; density is fetched and shown.

**Calibration**: `tools/calibrate-soon.py` replays history before the thresholds are fixed:
- Solar wind: NASA OMNI 1-minute data (OMNIWeb/SPDF, public domain), already time-shifted to the
  bow shock; Ey is insensitive to the extra few minutes.
- Activity: FMI R computed with the core's own method from FMI open data magnetometer archives
  for the same nights (as spec 002's recorded nights).
- At least 20 nights where a Lapland station reached Probable and 20 quiet nights, chosen from
  2024–2026 (solar maximum gives enough events). Threshold pairs per band are chosen to meet
  SC-003 with the fewest false "Likely" hours. The chosen nights are recorded as fixtures for
  `SoonReplayTests`.

Calibration data are used only offline to fix constants; nothing from OMNI is fetched by the
app (Principle I's licence check is recorded here anyway).

**Alternatives considered**: Bz threshold only (simple, but weak at low speed and misses fast
weak-Bz streams); OVATION model (global, coarse, a large file; rejected for the spec's
"now/soon" split).

**Result (2026-10-30, `tools/calibrate-soon.py`)**: 24 storm nights (Kp ≥ 5, a station of the
band reached Probable after the first hour of the night) and 22 quiet nights (Kp ≤ 2 all night),
September–March 2024–2026, in `Fixtures/outlook/soon-nights/` (`nights.json` lists them).

| Band | `possible` / `likely` (mV/m) | Rises seen coming | Quiet nights: dark time at Likely | at Possible or Likely |
|---|---|---|---|---|
| North | 1.25 / 2.5 | 18 of 24 (75%) | 0.1% | 2.0% |
| Central | 2.5 / 5.0 | 19 of 24 (79%) | 0% | 0.1% |
| South | 2.75 / 5.5 | 12 of 15 (80%) | 0% | 0% |

A rise counts as seen coming when the state was Possible or Likely at some 5-minute refresh from
75 to 15 minutes before it. The replay uses what the product would have held: samples observed
at L1 at least 8 minutes earlier, the last hour only.

How the data were prepared, and why:

- **FMI archive glitches.** Single bad 10 s samples lift R for exactly 10 minutes (R up to 65,842
  on 2024-09-05, even at Tartu). A level counts only when it is held for 15 consecutive minutes,
  both for the rise time here and for the night's level in R7.
- **OMNI timeshift.** OMNI's per-minute timeshift to the bow shock is noisy (5236 s, 1854 s and
  3674 s on consecutive minutes), so the L1 time is the row time minus the running median of
  the timeshift over an hour; the row time is used as the arrival.
- **OMNI plasma gaps.** About a quarter of OMNI's 1-minute speeds are missing (27% in October
  2025) where the field is present. Speed and density gaps of up to an hour are interpolated for
  the replay; Bz is never filled. Nights with less than 80% coverage were skipped.
- **Selection rule.** Per band, the highest `possible` that still sees the rises coming on at
  least ceil(70%) + 1 of the storm nights, with `likely` twice it as in the initial table. A first
  ranking by the fewest false Likely steps was rejected: every pair with a low enough `likely` has
  none, so it chose 1.25/3.12 for every band and ignored latitude.
- **Rises on quiet nights are left out.** A Lapland station reached Probable for 15 minutes on 9
  of the 22 quiet nights too. Counting those rises (33 North rises in all), the chosen North pair
  sees 19 (58%), and no pair meets 70% except the bottom of the grid (0.5/1.0 mV/m), which would
  say "may rise" on almost every night. Substorms on quiet nights are not predictable from the
  solar wind with a threshold rule; SC-003 is applied to the storm nights' rises, as this section
  planned.

## R7. Kp-to-activity mapping and calibration

**Decision**: per-band Kp thresholds for Possible and Probable
([outlook-rules.md](contracts/outlook-rules.md#2-expected-activity)), calibrated by
`tools/calibrate-kp.py`.

**Calibration**: for at least 30 nights across all bands (2024–2026), compare the band mapping
of the **observed** Kp (GFZ Potsdam definitive Kp, CC BY 4.0, offline only) with the highest
FMI activity level of that night at each zone's station (from the archive, as R6). Choose
thresholds that maximise agreement; SC-004 needs ≥ 80%. Results and the nights used become
`KpMappingTests` fixtures.

**Rationale**: Kp is global and 3-hourly, so only a coarse per-latitude mapping is honest. Bands
reuse the soon-rule bands so the user sees one consistent picture.

**Alternatives considered**: a per-station mapping (ten thresholds pairs, overfits 30 nights);
OVATION probability at the zone (global model, large file, not designed for a two-night
outlook).

**Result (2026-10-30, `tools/calibrate-kp.py`)**: 106 nights, September–March 2024–2026: the
soon calibration's nights plus up to 12 nights per Kp bucket (0–2, 2–3, 3–4, 4–5, 5–6, 6+),
1005 station-nights in `Fixtures/outlook/kp-nights.json`. Each station-night compares the highest
observed Kp over the station's relevant hours with the highest FMI level held for 15 consecutive
minutes in them (see R6 on glitches).

| Band | Possible from | Probable from | Agreement | With the initial values |
|---|---|---|---|---|
| North | 1 | 2.67 | 413 of 486 (85.0%) | 46.3% |
| Central | 2.67 | 4 | 361 of 413 (87.4%) | 57.9% |
| South | 5 | 5.67 | 83 of 106 (78.3%) | 72.6% |
| All | | | 857 of 1005 (85.3%) | |

SC-004 (≥ 80% over ≥ 30 nights) is met overall; the South band alone (one station, Tartu) is at
78%. The thresholds are much lower than the initial ones because, at this solar maximum, Lapland
stations held Probable for at least 15 minutes on most dark nights: FMI's levels describe the
most active moment of a long night, which is what the outlook is compared with.

## R8. Fetch cadence, caching and failures

**Decision**: a separate `OutlookService` actor, alongside `AuroraService`:

| Input | Due after | On failure |
|---|---|---|
| Solar wind | 5 min | Keep last samples; soon becomes Unknown once the newest is > 20 min old |
| Kp forecast | 60 min | Keep last; outlook for a night is unavailable if no block covers it |
| Alerts (watches) | 60 min | Keep last; no watch shown if none was ever fetched |
| Cloud forecast | 3 h | Keep last; clouds Unknown for hours not covered |

A failed fetch is retried on the next refresh (the app refreshes every 5 minutes in the
foreground), never in a loop. No background fetching is added: the outlook is foreground-only,
like the headline. Inputs are cached in `OutlookSnapshot` so the outlook can be recomputed for a
new time or place offline.

Network per hour in the foreground: ~24 KB solar wind + ~7 KB Kp/alerts + ~5 KB clouds.

**Rationale**: keeps every failure local (FR-020), adds nothing to the headline's path or its
1-second cached launch (SC-008), and stays far below any reasonable polling use (NWS asks only
that clients not hammer it; SWPC `max-age` is 60 s).

**Alternatives considered**: folding the new inputs into `AuroraService` (one actor, one cache):
a decode failure or slow NOAA response would sit on the headline's path. Rejected.

## R9. Alert text for "Moderate – bright moon" and release order

**Finding**: with chance-rules v2 a zone can be Moderate because of a bright moon (Probable,
dark, bright moon, clear). Today's `AlertMessage.make` would send `alert.body.someActivity`
("Some activity near %@ and a clear, dark sky"), which would be wrong. The service sends
localisation keys, so a new key must exist in every installed app that can receive alerts.

**Decision** (updated 2026-10-30: 2.0 went live on 2026-10-29 without the keys, so the
fallback below is now the plan):
1. This feature adds `alert.body.brightMoon` and `alert.body.brightMoon.cloudsUnknown` (fi, sv,
   en) to the **3.0** app and to `AlertMessage.bodyKeys` (the existing `AlertStringsTests`
   checks them).
2. `AlertMessage.make(for:moonKeys:)` sends the new keys only when `moonKeys` is true; otherwise
   it maps the moon case to `alert.body.twilight` (or `.cloudsUnknown`), whose text ("…but the
   sky is not fully dark yet") is the closest existing one.
3. The alert service reads `moonKeys` from the `ALERT_MOON_KEYS` setting, `false` by default.
   It is switched to `true` 30 days after 3.0 is in the App Store, without a new build. The
   server still learns nothing about the app version.

**Rationale**: the cheapest way to avoid showing raw keys to users, without the server learning
the app version (Principle II forbids storing device details).

## R10. Fixtures

**Decision**: `tools/record-outlook-fixtures.py` records, into
`Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/`:
- propagated solar wind on a quiet and an active day, plus a file with gaps and nulls;
- the Kp forecast in the new object shape, and one hand-made old-shape file;
- alerts.json with a G1 watch, a G2 watch and a cancellation (the 2026-10 messages seen in R3);
- the FMI cloud forecast for all ten zones;
- a 404 body and a malformed body for failure tests.

Calibration fixtures come from R6 and R7, moon references from R4.

## R11. Text and localisation

New strings in fi, sv and en (about 45): the soon states and lines (with a time placeholder),
the outlook rows and reasons including "geomagnetic storm watch" and G levels, the eight moon
phase names, the moon details, solar wind details, the "this is a forecast" note, attribution,
and the two alert keys (R9). Final wording is done with the UI work; keys are fixed in the
contracts.

## R12. Licence, attribution and privacy

- **NOAA SWPC**: NWS web content is public domain unless noted otherwise
  (weather.gov/disclaimer, linked from SWPC's footer); no credit is required, but the app credits
  "NOAA Space Weather Prediction Center" (FR-021) and uses no NOAA or NWS logo, which NWS treats
  as trademarks. NWS gives no availability guarantee and may block clients that harm its
  service; the cadence in R8 is far below that.
- **FMI**: CC BY 4.0, unchanged attribution.
- **Calibration only** (not fetched by the app): NASA OMNI (public domain), GFZ Kp (CC BY 4.0,
  credited in the calibration notes), JPL Horizons (public domain).
- **Privacy**: requests carry no user data and are identical for every user. NOAA servers are in
  the US and see the device's IP address, like any server; the privacy policy names NOAA as a
  contacted server (FR-022). No new entries in `PrivacyInfo.xcprivacy` are needed (no tracking
  domains, no new required-reason APIs). The App Store label stays "Data Not Collected".
