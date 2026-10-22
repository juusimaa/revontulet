# Feature Specification: Aurora Main Screen

**Feature Branch**: `main` (solo pre-release workflow; no feature branch)

**Created**: 2026-10-22

**Status**: Draft

**Input**: User description: "Main screen that show probability of aurora borealis and current location. Also nearest measurement location should be shown that where data is from. Probability is calculated from R value like fmi.fi does."

## Clarifications

### Session 2026-10-22

- Q: How should the headline chance to see be shown to the user? → A: Four named levels: None,
  Low, Moderate, High, each with a short reason (e.g. "Low – overcast"); no percentage.
- Q: Which languages should the app's text be in for this first feature? → A: Finnish, Swedish
  and English.
- Q: When location access is denied, what should the user pick by hand: a measurement station or
  a place? → A: A Finnish municipality from a searchable list; the nearest station is picked
  automatically.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See my chance of seeing the aurora (Priority: P1)

On a dark evening, the user opens the app to decide whether it is worth going outside to look
for the northern lights. The main screen shows, at a glance, the chance of seeing the aurora at
their current location, combining geomagnetic activity (from the nearest magnetometer station's
R value, as fmi.fi calculates it), darkness and cloud cover. It also shows the name of their
location, the station the activity data comes from, and how recent the data is.

**Why this priority**: This is the whole purpose of the app. Without it there is no product.

**Independent Test**: With location access granted and FMI data available, open the app and
verify that the screen shows the chance to see, the user's location name, the nearest station's
name and distance, and the data time; that the geomagnetic activity level matches the FMI method
for the station's current R value; and that darkness and cloud cover are reflected in the chance.

**Acceptance Scenarios**:

1. **Given** location access is granted and current FMI data is available, **When** the user
   opens the app, **Then** the main screen shows the chance to see the aurora at the user's location,
   the location name, the nearest station's name and its distance from the user, and the time of
   the latest measurement.
2. **Given** the nearest station's latest R value falls into a given FMI probability level,
   **When** the main screen is shown, **Then** the displayed geomagnetic activity level is the same
   one fmi.fi would show for that station and R value.
3. **Given** high geomagnetic activity, **When** it is daytime or the sky is overcast at the
   user's location, **Then** the chance to see is lowered accordingly and the screen names the
   limiting factor (too light, or clouds).
4. **Given** high geomagnetic activity, a dark sky and little cloud, **When** the main screen is
   shown, **Then** the chance to see is at its highest level for that activity.
5. **Given** the user moves so that a different station becomes the nearest, **When** the main
   screen is next refreshed, **Then** it shows the new nearest station and the resulting chance
   to see.
6. **Given** the main screen is shown, **When** the user looks for more detail, **Then** the
   current R value, the station, the measurement time and the data source (FMI) with attribution
   are available without leaving the main screen.

---

### User Story 2 - Instant, honest result even with poor connectivity (Priority: P2)

The user is often outdoors, in the dark and far from good mobile coverage. When they open the
app, they immediately see the last known result, clearly marked with its age, and the screen
updates when fresh data arrives. If no fresh data can be fetched, the app says so instead of
showing a blank or misleading screen.

**Why this priority**: The main screen is only trustworthy if the user always knows how old the
information is. It builds directly on Story 1.

**Independent Test**: Open the app once online, then reopen it with networking disabled; verify
that the last result appears immediately, marked as not current, and that a clear offline message
is shown.

**Acceptance Scenarios**:

1. **Given** the app has shown a result before, **When** the user opens it again, **Then** the
   last known result is shown immediately, with its measurement time, before any new data is
   fetched.
2. **Given** new data becomes available while the screen is open, **When** it has been fetched,
   **Then** the screen updates without user action.
3. **Given** the device is offline, **When** the user opens the app, **Then** the last known
   result is shown marked as outdated, together with a message that new data cannot be fetched.
4. **Given** the newest available measurement is older than the staleness limit, **When** the
   main screen is shown, **Then** the result is visibly marked as outdated.
5. **Given** the user wants the latest data, **When** they ask the screen to refresh, **Then** the
   app fetches new data and shows the outcome (updated, or an explanation of why not).

---

### User Story 3 - Use the app without sharing location (Priority: P3)

A user who does not want to share their location, or who wants to check another area (e.g. their
summer cottage), searches for a Finnish municipality and sees the chance to see the aurora there.
The nearest measurement station is picked automatically.

**Why this priority**: Required by the project's privacy principle, but most users will grant
location access.

**Independent Test**: Deny location access, choose a municipality and verify that the main screen
shows the chance to see there, based on the station nearest to that municipality; relaunch and
verify that the choice is remembered.

**Acceptance Scenarios**:

1. **Given** location access has been denied, **When** the user opens the app, **Then** the main
   screen explains that location is not available and offers to choose a municipality.
2. **Given** the municipality list, **When** the user types part of a name in Finnish or Swedish,
   **Then** matching municipalities are shown and can be selected.
3. **Given** the user has chosen a municipality, **When** the main screen is shown, **Then** it
   shows the chance to see at that municipality (activity, darkness and cloud cover), the nearest
   station with its distance, the R value and data time, and indicates that the location was
   chosen manually rather than being the current location.
4. **Given** a manually chosen municipality, **When** the user relaunches the app, **Then** the
   same municipality is still used until the user changes it or switches back to current location.

---

### Edge Cases

- The user is outside Finland: the app covers Finland only, so no chance is shown for the current
  location; the screen explains that the location is outside the coverage area and offers to
  choose a municipality.
- The nearest station has no recent data (station outage): the next nearest station with recent
  data is used, and the screen says that a more distant station is being used.
- FMI data cannot be fetched at all and there is no cached result (first launch offline): the
  screen explains that data is needed and offers a retry; no chance is shown.
- Location is still being determined: the last known result is shown; if none exists, a waiting
  state is shown, not an empty screen.
- Location access is "approximate" only: the app works normally, since station-level accuracy is
  sufficient.
- The user is between two stations at nearly equal distance: the nearest one is used, and the
  choice does not flip back and forth on each refresh.
- Daytime or bright summer nights, when aurora cannot be seen even with high activity: the chance
  to see is shown as none or very low, and the screen says it is too light, while still showing the
  geomagnetic activity level.
- Overcast sky with high activity: the chance to see is lowered, and the screen says that clouds
  are the limiting factor.
- Cloud data is unavailable but magnetometer data is available: the geomagnetic activity level and
  darkness are still shown, and the screen says that cloud cover is unknown and not included.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main screen MUST show, as its headline, the chance of seeing the aurora at the
  user's location as one of four named levels — None, Low, Moderate, High — together with a short
  reason (e.g. "Low – overcast"). No percentage is shown. The chance MUST combine three factors:
  geomagnetic activity, darkness and cloud cover.
- **FR-001a**: The geomagnetic activity factor MUST use the same probability levels and
  thresholds that fmi.fi uses for the R value of the relevant station, and this FMI level MUST
  also be shown on its own.
- **FR-001b**: The darkness factor MUST be based on the sun's position at the user's location at
  the current time (day, twilight stages, night).
- **FR-001c**: The cloud cover factor MUST be based on FMI open data for cloud cover at or near the
  user's location for the current time.
- **FR-001d**: The rules for combining the three factors MUST be fixed, documented and visible to
  the user in plain language (e.g. "High activity, but overcast"). The main screen MUST show which
  factor most limits the chance.
- **FR-001e**: Coverage is Finland only. When the user's current location is outside Finland, the
  app MUST NOT show a chance for it, MUST say that the location is outside the coverage area, and
  MUST offer manual municipality selection.
- **FR-002**: The R value MUST be calculated from FMI's open magnetometer data using the same
  definition FMI uses, and the result MUST match FMI's published value for the same station and
  time.
- **FR-003**: The main screen MUST show the user's current location as a recognisable place name
  (e.g. town or municipality).
- **FR-004**: The main screen MUST show the measurement station the activity data comes from: its
  name and its distance from the user.
- **FR-005**: The station used MUST be the nearest station to the user that has recent data.
- **FR-006**: The main screen MUST always show the time of the measurement the chance is
  based on, and MUST mark the result as outdated when that measurement is older than 1 hour.
- **FR-007**: The main screen MUST make the current R value, the data source (FMI) and the
  required data attribution available without navigating away.
- **FR-008**: On launch, the last known result MUST be shown immediately if one exists, and then
  updated when new data has been fetched.
- **FR-009**: While the app is open, the result MUST be refreshed automatically at least as often
  as new FMI data is published, and the user MUST be able to request a refresh manually.
- **FR-010**: The app MUST work without location access by letting the user choose a Finnish
  municipality from a searchable list (searchable by Finnish and Swedish names). The chance to see
  is then calculated for that municipality, using its nearest station. Choosing a municipality
  MUST NOT require a network request, and the choice MUST persist across launches until changed.
- **FR-011**: The user's precise location MUST NOT be sent off the device; it is used only to
  determine the nearest station, the place name, darkness, and which cloud cover data applies.
  Cloud cover data MUST be requested for a coarse area or nearby observation point, not for the
  user's exact coordinates.
- **FR-012**: The main screen MUST have explicit states for: loading, offline, outdated data, no
  data available, location denied, and location being determined.
- **FR-013**: The main screen MUST be fully usable with VoiceOver, Dynamic Type, Dark Mode, and
  Reduce Motion / Reduce Transparency, and the chance and activity levels MUST NOT be
  communicated by colour alone.
- **FR-014**: All user-facing text, including level names, reasons, states, accessibility labels
  and attribution, MUST be available in Finnish, Swedish and English. The app MUST follow the
  device language and fall back to English for any other language. Dates, times and distances
  MUST be formatted for the selected language and region.

### Key Entities

- **Measurement station**: A magnetometer station in FMI's network. Name, geographic position,
  and whether it currently has recent data.
- **R value**: FMI's local magnetic activity measure for one station over a time period, with
  the measurement time it refers to.
- **Geomagnetic activity level**: The probability level derived from a station's R value
  following FMI's method, with the station and time it is based on.
- **Darkness**: Whether it is day, twilight or night at the user's location at a given time.
- **Cloud cover**: How much of the sky is covered by cloud at or near the user's location, with the
  time and the source point it refers to.
- **Chance to see**: The headline level (None, Low, Moderate or High) combining geomagnetic
  activity, darkness and cloud cover, with the factor that limits it most and a short reason.
- **User location**: The user's current position or a manually chosen municipality, used only
  on the device; has a display place name and a source (current location or manual choice).
- **Municipality**: A Finnish municipality with its Finnish and (where it exists) Swedish name and
  a representative position, used for manual selection.
- **Cached result**: The last shown chance to see with its activity level, darkness, cloud
  cover, station, R value and measurement time, kept so it can be shown on the next launch.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time user can tell whether it is worth going outside to look within
  5 seconds of the main screen appearing.
- **SC-002**: On repeat launches, a result is visible within 1 second of opening the app.
- **SC-003**: For a set of at least 20 recorded historical cases, the geomagnetic activity level
  shown matches the level fmi.fi showed for the same station and time in 100% of cases.
- **SC-003a**: For a set of reference situations (e.g. high activity at noon, high activity under
  full overcast, high activity on a clear dark night), the chance to see follows the documented
  combination rules in 100% of cases, and the limiting factor shown is the correct one.
- **SC-004**: When online, the shown measurement is never more than one FMI publishing interval
  behind the latest data FMI has published.
- **SC-005**: In usability testing, 9 out of 10 users can correctly name the station the
  activity data comes from and how old the data is.
- **SC-006**: The app's privacy disclosure can state that no user data is collected.

## Assumptions

- The R value and the probability levels and thresholds follow FMI's published aurora and space
  weather service; the exact definitions are confirmed from FMI documentation during planning,
  and are not invented by the app.
- FMI's open magnetometer data is freely available for the stations in its network, is updated
  at least hourly, and its licence allows use in the app with attribution.
- The set of stations is the one FMI uses for its own aurora probability service. Coverage is
  Finland only for now; locations outside Finland's borders are treated as outside coverage.
- FMI's open data includes cloud cover observations and/or forecasts covering all of Finland, free
  to use with attribution; the exact data set is chosen during planning.
- The combination of activity, darkness and cloud cover is the app's own documented rule, not an
  FMI product; only the geomagnetic activity level is claimed to match fmi.fi.
- "Nearest" means straight-line distance from the user to the station.
- The place name is shown at town or municipality level; it is derived in a way that does not
  send precise coordinates off the device.
- The staleness limit for marking data outdated is 1 hour (FR-006), based on hourly R values.
- Manual selection is by municipality; each municipality's representative position (e.g. its
  centre) is used for darkness, cloud cover and the nearest station. The municipality list comes
  from an open official source and is bundled with the app.
- Notifications, forecasts, history graphs, maps and widgets are out of scope for this feature.
- Station and place names are shown as published by their source (FMI for stations) and are not
  translated, except where an official Swedish name exists for a place.
