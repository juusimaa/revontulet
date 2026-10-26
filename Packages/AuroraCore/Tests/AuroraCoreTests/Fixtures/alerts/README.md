Recorded FMI data for alert evaluation tests, one folder per night (`<YYYYMMDD>/`, the local
date of the evening), recorded with `tools/record-fixtures.py --alert-night` (T016). Each night
covers 15:00–05:00 UTC.

| Night | Kind | What happened |
|---|---|---|
| `20261014` | strong | R red at KEV, KIL, MUO and TAR; 10 alerts (Moderate and High) in 6 zones |
| `20261018` | quiet | Possible activity in the far north only; 3 Moderate alerts, no High anywhere |
| `20261019` | moderate | Possible at IVA and PEL under clear skies; 2 Moderate alerts |
| `20261024` | strong, overcast | R red at KEV (FMI reference up to 303) but overcast or partly cloudy everywhere; no alerts. Crosses the end of daylight saving time. Has `reference-r.json` |

Files per night:

- `magnetometer-<CODE>.csv`: 10 s X/Y/Z averages per station (`time,x,y,z`, empty for NaN).
- `clouds.csv`: TotalCloudCover rows for Finland (`time,latitude,longitude,octas`).
- `night.json`: the night window.
- `reference-r.json` (only `20261024`): FMI's published R, from the FMI chart, which keeps only
  about 24 hours. `tools/alert-reference.py` reports how its R compares: activity levels agree on
  1566 of 1570 points; the differences are at 00:00 UTC, where FMI's own series resets.
- `expected.json`: the alerts (`zone`, `level`, `time`) the night must produce when replayed in
  5-minute cycles, written by `tools/alert-reference.py`, an independent Python implementation
  of the R, chance and alert rules. Each alert was reviewed against the printed R, darkness,
  clouds and reason.

The tests rebuild each FMI request the service would make (magnetometer 12 minutes back every
5 minutes, clouds 30 minutes back every 10 minutes) from these rows, instead of storing hundreds
of MB of XML responses per night.

The other 17 of SC-002's 20 reference nights are synthetic sequences in `AlertPolicyTests`.
