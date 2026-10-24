# Contract: Alert Settings States

The alert settings screen, reached from the main screen. Every state is designed explicitly
(Principle VI); the UI itself is built with the `ios-ui-craft` skill during implementation.

| State | When | Shows | Actions |
|---|---|---|---|
| **Off, first time** | Alerts never turned on | What alerts do; what is sent (anonymous notification address, zone, threshold), where (alert service in Finland), that turning off deletes it; privacy policy link (FR-002) | Threshold picker (default High), "Turn on alerts" |
| **Off** | Turned off before | Short description, privacy link | Threshold picker, "Turn on alerts" |
| **Asking permission** | User tapped turn on, iOS prompt showing | System prompt | — |
| **Permission denied** | Notifications denied in iOS Settings | "Notifications are off for Revontulet" | "Open Settings" |
| **On, confirming** | Change sent but not yet confirmed (offline, service down, retrying) | Zone, threshold, "Waiting to confirm" (no error dialog, FR-005) | Change threshold, turn off |
| **On** | Confirmed | Zone ("Area: Oulujärvi"), threshold, "Confirmed <relative date>" | Change threshold, send test, turn off |
| **On, no dark nights** | On, and it is too light at the zone for the next 24 h | As On, plus "Alerts resume when nights get dark again" | As On |
| **Turning off** | Off chosen, deletion not yet confirmed | Alerts shown **off** immediately (FR-006), small "Removing…" note | Turn on again |
| **No zone yet** | No place in Finland has ever been resolved (e.g. outside Finland with location only) | "Choose a place in Finland first" | Open place picker |
| **Test sent / limited** | After "Send test" | "Test alert sent" or "Try again at 21:40" (429) | — |

Also on the main screen: a toolbar button that opens the settings. It shows a filled bell while
alerts are on, with an accessibility label stating on or off, never relying on the symbol alone.
