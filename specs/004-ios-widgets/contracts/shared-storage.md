# Contract: Shared on-device storage

Applies to the app and the `RevontuletWidgets` extension. Local to the device; nothing here is
transmitted (constitution II).

## App Group

- Identifier: `group.fi.juusimaa.revontulet`.
- Enabled on both App IDs by hand before the first Xcode Cloud build
  (`fi.juusimaa.revontulet`, `fi.juusimaa.revontulet.widgets`).
- Both entitlements files list it under `com.apple.security.application-groups`.

## Files (in the group container root)

| File | Content | Format |
|---|---|---|
| `last-result.json` | the last `AuroraResult` | JSON, as today |
| `last-outlook.json` | the last `OutlookSnapshot` | JSON, as today |

- Written atomically; excluded from backup; created with intermediate directories if missing.
- Unreadable or undecodable content reads as "nothing cached".
- A format change in the core types invalidates the file once, as today (`AuroraResult` already
  documents this for the moon field).

## Defaults (suite = the group identifier)

| Key | Values | Writer |
|---|---|---|
| `placeSelection` | `"currentLocation"` or a Statistics Finland municipality code | app only |

Missing key means `currentLocation`. The extension reads it and never writes it.

## Migration (app only, once, before the caches are created)

1. If `last-result.json` is missing in the group container and exists in Application Support, copy
   it over. Same for `last-outlook.json`.
2. If the suite has no `placeSelection` and `UserDefaults.standard` has one, copy it.
3. Leave the old files and value in place (a later version may remove them). A failure to copy only
   costs the instant result on the next launch, as an unreadable cache does today.

Tests (app XCTest, temporary directories and suites): copy happens once; an existing group file is
never overwritten; missing source is fine; selection copied; the extension code path has no
migration.

## Access rules

- The app and the widget write the result and outlook files only after a successful fetch; a failed
  or cancelled fetch writes nothing.
- The widget does not write the selection, the place or any file other than the two above.
- Deleting the app deletes the group data with it. Removing all widgets leaves only the files the
  app itself uses; no widget process runs.
