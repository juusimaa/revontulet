# Contract: Main Screen States

The user-facing contract for the main screen (FR-012). Visual design is done with the
`ios-ui-craft` skill (Principle VI); this file fixes only what each state must show.

## Content when a result exists

| Element | Always visible | Detail (on the main screen, e.g. expandable) |
|---|---|---|
| Chance level + reason ("Low – overcast") | ✓ | |
| Place name + source (current location / chosen municipality) | ✓ | |
| Measurement time / age ("8 min ago") | ✓ | |
| Outdated badge (measurement > 30 min old) | when applicable | |
| Station name + distance | ✓ | |
| Activity level (FMI wording) | | ✓ |
| R value | | ✓ |
| Darkness (too light / twilight / dark) | | ✓ |
| Cloud cover (octas, station, distance) or "not included" | | ✓ |
| "More distant station used" note | when applicable | |
| Attribution: FMI and Statistics Finland, CC BY 4.0 | | ✓ |

Levels and reasons are text, never colour alone (FR-013).

## States

| State | Trigger | Shows | Actions |
|---|---|---|---|
| Loading (first run) | No cache, fetch in progress | Progress + "Fetching aurora data" | — |
| Determining location | Waiting for first location fix | Cached result if any; else waiting message | Choose municipality |
| Result | Valid result | Content above | Refresh, change place |
| Outdated | Result measurement > 30 min old | Content + outdated badge | Refresh |
| Offline | Last fetch failed (network) | Cached result marked outdated + offline message | Retry |
| No data | No cache and fetch failed, or no station has valid R | Explanation, no chance | Retry |
| Location denied | Permission denied/restricted, no manual place | Explanation | Choose municipality, open Settings |
| Outside coverage | Current location outside Finland | "Outside coverage area (Finland only)" | Choose municipality |

## Refresh behaviour

- On launch and on return to foreground: show cache immediately (≤ 1 s, SC-002), then refresh.
- While in the foreground: refresh every 5 minutes.
- Pull to refresh (or button): forced refresh, debounced to once per 30 s.
- A refresh never replaces a valid result with an empty screen.
