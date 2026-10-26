# Feature Specification: Aurora Outlook

**Feature Branch**: `003-aurora-outlook`

**Created**: 2026-10-26

**Status**: Draft

**Input**: User description: "Aurora outlook: FMI R stays the main "now" signal. NOAA SWPC real-time solar wind (Bz, speed, density from L1) gives a "soon" signal (next ~30–60 min). The NOAA Kp forecast and geomagnetic storm watches give a "tonight/tomorrow" outlook. The moon (illumination and altitude, computed on device) becomes another visibility factor next to darkness and clouds. Open data only (NOAA SWPC is public domain), no user location in requests, logic lives in portable AuroraCore. Languages fi, sv, en."

## Overview

Today the app answers one question: "Is the aurora visible near me **now**?" It answers from
FMI's R value, darkness and cloud cover (spec 001). This feature adds two further time horizons
without changing that answer:

| Horizon | Question | Main signal |
|---|---|---|
| Now | Should I go out and look? | FMI R value at the nearest station (unchanged) |
| Soon (next ~30–60 min) | Is activity about to rise? | Solar wind measured upstream of Earth (NOAA SWPC) |
| Tonight / tomorrow night | Is it worth planning for? | Kp forecast and geomagnetic storm watches (NOAA SWPC) |

It also adds the moon as a visibility factor: a bright moon washes out faint aurora in the same
way that twilight does.

## Clarifications

### Session 2026-10-26

- Q: Should alerts use the new signals? → A: No. Alerts stay as in spec 002 and only gain the moon
  through the shared chance rules. A "soon" alert may follow as a separate feature once the
  "soon" rule has been checked against recorded data.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Moonlight is part of the chance to see (Priority: P1)

On a clear, dark night with low activity, the user checks the app. A nearly full moon is high in
the sky, so faint aurora would be hard to see. Instead of "Low – low activity", the app shows
"None – bright moon". The details panel shows the moon's phase and whether it is up.

**Why this priority**: It makes the existing headline more accurate on every night of the month,
needs no new data source or network request, and the "soon" and "tonight" signals reuse it.

**Independent Test**: Run the reference cases for the updated chance rules (activity, darkness,
moon, clouds) and check that every level and limiting factor matches the documented table. In the
app, set a time and place with a known bright moon (synthetic data) and check the headline, the
reason and the moon details.

**Acceptance Scenarios**:

1. **Given** low activity, a dark clear sky and a bright moon above the horizon, **When** the
   user opens the app, **Then** the chance is one level lower than without the moon and the
   reason says "bright moon".
2. **Given** high activity, twilight and a bright moon, **When** the chance is calculated,
   **Then** it is lowered by one level only, not two, because twilight and moonlight together
   count as one sky-brightness step.
3. **Given** a full moon below the horizon, **When** the chance is calculated, **Then** the moon
   does not change the level, and the details say the moon is below the horizon.
4. **Given** the alert service checks a zone, **When** the moon is bright at the zone's
   representative position, **Then** the zone's chance includes the moon exactly as the app does.

---

### User Story 2 - Know whether activity is about to rise (Priority: P2)

The user is outside or about to go to bed. The headline says "Low – low activity", but the solar
wind measured upstream of Earth has just turned strongly favourable for aurora. A "Soon" line
under the headline says "Activity likely to rise within the hour", so the user waits a little
longer or sets a reminder.

**Why this priority**: The R value only rises once the aurora is already active. Solar wind
measurements give roughly 30–60 minutes of warning, which is the most useful lead time for
someone deciding whether to stay out.

**Independent Test**: Replay recorded solar wind data from known substorm nights and quiet
nights, and check that the "soon" signal and its wording follow the documented rule, and that the
headline level does not change.

**Acceptance Scenarios**:

1. **Given** recorded solar wind conditions that meet the "likely" rule, **When** the app
   refreshes, **Then** the main screen shows "Activity likely to rise" with an approximate time
   window, and the headline chance is unchanged.
2. **Given** quiet solar wind conditions, **When** the app refreshes, **Then** no "soon" warning is
   shown and the details say "No sign of rising activity".
3. **Given** it is too light now and will stay too light for the next hour, **When** conditions
   meet the "likely" rule, **Then** no "soon" line is shown on the main screen; the details still
   show the solar wind state.
4. **Given** the solar wind data is older than the staleness limit or cannot be fetched, **When**
   the main screen is shown, **Then** the "soon" line is hidden, the details say the solar wind
   data is unavailable, and nothing else on the screen changes.

---

### User Story 3 - Plan for tonight and tomorrow night (Priority: P3)

In the afternoon, the user wants to know whether tonight or tomorrow night is worth staying up
for. The main screen shows a short outlook: "Tonight: Moderate – geomagnetic storm watch" and
"Tomorrow night: Low – cloudy". The details explain what the outlook is based on and that it is
a forecast, not a measurement.

**Why this priority**: It adds planning value, but forecasts are less certain and the user can
already check the app in the evening. It is the largest part of the feature.

**Independent Test**: Use recorded Kp forecasts, storm watches and cloud forecasts for a fixed
place and date, and check that both nights' outlook levels, reasons and storm watch notes follow
the documented outlook rule.

**Acceptance Scenarios**:

1. **Given** a Kp forecast for tonight that maps to "Possible" activity for the user's zone, a
   dark night, no bright moon and a clear cloud forecast, **When** the user opens the app,
   **Then** the outlook for tonight is "Moderate".
2. **Given** a geomagnetic storm watch issued for tomorrow, **When** the user opens the app,
   **Then** the outlook for tomorrow night mentions the storm watch and its level (e.g. G2).
3. **Given** a date in early summer when it does not get dark at the user's location, **When**
   the user opens the app, **Then** both nights' outlook is "None – too light", whatever the
   forecast says.
4. **Given** the forecast data cannot be fetched and no recent copy is cached, **When** the user
   opens the app, **Then** the outlook section says the outlook is unavailable, and the "now"
   result is unaffected.
5. **Given** it is currently night, **When** the user views the outlook, **Then** "tonight" means
   the dark period that is under way, not the next one.

---

### Edge Cases

- **Solar wind data gaps**: the upstream spacecraft data has gaps and occasional spacecraft
  switches. A gap means "soon" is unknown, never "quiet".
- **Contradicting signals**: the solar wind looks quiet but R is already High (or the other way
  round). The headline always follows R; the "soon" line describes only what the solar wind
  suggests, worded so that it does not contradict the headline (e.g. "Activity may stay high"
  rather than "No sign of activity").
- **Headline already High**: the "soon" line is shown only if the solar wind suggests activity
  will continue or rise; it never lowers the headline.
- **Overcast now**: the "soon" line still appears when activity is likely, with a note that the
  sky is overcast, because clouds may clear locally.
- **Outside Finland or no place chosen**: no outlook or "soon" signal is shown, as for the
  headline (spec 001, FR-001e).
- **Polar night and midnight sun**: the darkness and moon rules handle both; in polar night the
  moon can be up for the whole night or not rise at all.
- **New moon or moon below the horizon**: the moon is reported but has no effect.
- **Storm watch for a period that has already started**: it applies to tonight.
- **Several storm watches**: the highest level for each night is shown.
- **Cloud forecast missing for a night**: the outlook uses activity, darkness and moon only, and
  says cloud cover is not included, as the headline does.
- **Clock and time zones**: forecasts in UTC are matched to the local dark period of the user's
  place in Finnish local time, including the change to and from daylight saving time.

## Requirements *(mandatory)*

### Functional Requirements

#### Now: moon as a visibility factor

- **FR-001**: The moon's illuminated fraction and altitude MUST be calculated on the device for
  the user's place and time, with no network request.
- **FR-002**: The moon MUST count as **bright** when it is above the horizon and at least half
  illuminated. Planning MAY adjust these thresholds with a documented reason before they are
  fixed in the rules.
- **FR-003**: The chance-to-see rules (spec 001, FR-001d) MUST be extended so that a bright moon
  lowers the level by one step, like twilight. Twilight and a bright moon together MUST lower it
  by one step only (one "sky brightness" step). "Too light" and "Overcast" still set the level to
  None. When the moon is the only factor that lowered the level, the limiting factor and reason
  MUST be "bright moon".
- **FR-004**: The details MUST show the moon's phase (as an illuminated percentage and a phase
  name) and whether it is up, in all three languages.
- **FR-005**: Every place that uses the chance-to-see rules MUST use the extended rules: the main
  screen, the widgets, the map and the alert service. This keeps an alert consistent with the app
  (spec 002, FR-008).

#### Soon: solar wind

- **FR-006**: The app MUST derive a "soon" state from real-time solar wind measurements published
  by NOAA's Space Weather Prediction Center: the north–south component of the interplanetary
  magnetic field (Bz) and the solar wind speed. The density is shown in the details but is not
  part of the rule.
- **FR-007**: The "soon" state MUST be one of: **Quiet** (no sign of rising activity),
  **Possible** (activity may rise), **Likely** (activity likely to rise), or **Unknown** (data
  missing or older than 20 minutes). The rule MUST be fixed, documented and based on conditions
  that persist for a minimum period, so that one short spike does not trigger it. The thresholds
  are set in planning and tested against recorded events (SC-003).
- **FR-008**: When the state is Possible or Likely, the main screen MUST show a "soon" line under
  the headline with an approximate time window based on NOAA's modelled arrival time of the solar wind
  at Earth (e.g. "within about 45 minutes"), rounded to avoid false precision.
- **FR-009**: The "soon" state MUST NOT change the headline chance or its level. It MUST be
  visually and textually distinct from the headline, so that a user never mistakes a forecast for
  a measurement.
- **FR-010**: The "soon" line MUST NOT be shown on the main screen when it is too light now and
  will stay too light for the whole time window. The details MUST always show the current state,
  including Quiet and Unknown.

#### Tonight and tomorrow night: outlook

- **FR-011**: The app MUST show an outlook for two nights: **tonight** (the current or next dark
  period at the user's place) and **tomorrow night** (the one after it).
- **FR-012**: Each night's expected activity MUST come from NOAA's planetary Kp forecast, using
  the highest Kp forecast for the dark hours of that night. It is mapped to the FMI activity
  levels (Unlikely, Possible, Probable) for the user's zone with a fixed, documented,
  latitude-dependent mapping. The mapping is calibrated in planning against recorded Kp and FMI
  data (SC-004).
- **FR-013**: Active geomagnetic storm watches from NOAA for a night MUST be shown with that
  night's outlook, with the storm level (G1–G5) in plain language. A watch MAY raise the night's
  expected activity by the mapping for its expected Kp, but MUST NOT lower it.
- **FR-014**: Each night's outlook MUST be a level from the same four levels as the headline
  (None, Low, Moderate, High) with a reason. It combines the expected activity with that night's
  darkness, the moon and an FMI cloud cover forecast, using the same combination rules as the
  headline. "Darkness" for a night is the darkest part of its dark hours, and "moon" is the moon
  during the dark hours.
- **FR-015**: The cloud forecast MUST be requested for the zones' representative positions (the
  measurement station zones from spec 002), never for the user's own coordinates. When it
  is missing, the outlook MUST say that cloud cover is not included.
- **FR-016**: The outlook MUST be clearly labelled as a forecast, and its details MUST say what it
  is based on and when the forecast data was last updated.

#### Data, privacy and reliability

- **FR-017**: The new data MUST be fetched from openly published sources only: NOAA SWPC products
  (solar wind, Kp forecast, alerts and watches) and FMI open data (cloud forecast). The licence
  and terms of use of each source MUST be recorded in the plan before it is used (Principle I).
- **FR-018**: Requests for the new data MUST NOT contain anything derived from the user (no
  location, zone or identifier); every user sends the same requests (Principle II).
- **FR-019**: Each source MUST be fetched no more often than it updates: solar wind at most every
  5 minutes while the app is open, and the Kp forecast, watches and cloud forecast at most once an
  hour. Results MUST be cached and shown from cache on launch (Principle V).
- **FR-020**: Failure of any new source MUST NOT affect the "now" result or any existing feature.
  Each section MUST have its own unavailable or outdated state, and data age MUST be visible in
  the details.
- **FR-021**: NOAA SWPC MUST be credited as a data source next to FMI in the app's attribution.
- **FR-022**: The privacy policy MUST name NOAA as a server the app contacts, and say that the
  request includes nothing about the user. The App Store privacy label MUST stay "Data Not
  Collected".
- **FR-023**: All new text, including states, reasons, the moon phase names, storm levels and
  accessibility labels, MUST exist in Finnish, Swedish and English, and the new sections MUST
  meet the accessibility rules of spec 001 (FR-013).
- **FR-024**: All new domain logic (moon position, "soon" rule, Kp mapping, outlook rule, parsing
  of the new data) MUST live in the shared core package and be tested with recorded data.
- **FR-025**: Alerts MUST NOT use the "soon" state or the outlook. They stay as specified in spec
  002 and change only through the moon in the shared chance rules (FR-005). The alert service
  MUST NOT fetch NOAA data for this feature.

### Key Entities

- **Moon state**: For a place and time: illuminated fraction, phase name, altitude, and whether
  it counts as bright.
- **Sky brightness**: The combined light factor from darkness and moon (Too light, Bright —
  twilight or bright moon —, Dark), with which of the two caused it.
- **Solar wind sample**: One upstream measurement: time, Bz, speed, density, and how old it is.
- **Soon state**: Quiet, Possible, Likely or Unknown, with the approximate time window, the data
  time and the solar wind values it is based on.
- **Kp forecast**: The forecast planetary Kp for consecutive 3-hour periods, with when it was
  last updated.
- **Storm watch**: A geomagnetic storm watch with its level (G1–G5), the period it covers and its
  issue time.
- **Night**: A dark period at a place, from when it gets dark to when it gets light, in local
  time.
- **Night outlook**: For one night: expected activity level, darkest sky brightness, moon, cloud
  forecast, storm watches, the resulting level (None–High) and reason, and when the forecasts
  were last updated.

## Privacy Review (Principle II)

- **No new data leaves the device.** NOAA products are global files that are the same for every
  user, and requests carry no parameters about the user. Like every server, NOAA sees the
  device's IP address. This is the same as for FMI today and is disclosed in the privacy policy
  (FR-022).
- **Cloud forecast** requests ask for all ten zone positions at once, so the request is the same
  for every user and reveals nothing about where the user is.
- **The moon** is calculated on the device.
- **No backend data change** (FR-025). The alert service only applies the moon, which it
  calculates itself; what it receives, stores and fetches does not change.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The extended chance rules give the documented level and limiting factor in 100% of
  the reference cases, including all combinations of twilight, bright moon and clouds.
- **SC-002**: The calculated moon altitude is within 1° and the illuminated fraction within 2
  percentage points of published astronomical values, for at least 20 reference times and places
  in Finland.
- **SC-003**: For a recorded set of at least 20 nights in which a Lapland station's FMI activity
  rose to Probable, the "soon" state was Possible or Likely at least 15 minutes before the rise in
  at least 70% of cases. For at least 20 recorded quiet nights, the state is Likely for no more
  than 10% of the dark hours.
- **SC-004**: When the outlook mapping is applied to the Kp that was actually observed, it gives
  the same activity level as the highest FMI level of that night at the zone's station on at
  least 80% of at least 30 recorded nights spread across Finland's zones.
- **SC-005**: In usability testing, 9 out of 10 users correctly say which of the screen's results
  is a current measurement and which are forecasts.
- **SC-006**: A first-time user can still tell within 5 seconds whether it is worth going out now
  (spec 001, SC-001), with the new sections on the screen.
- **SC-007**: With all NOAA sources unreachable, the "now" result, widgets, map and alerts work as
  before in 100% of the existing tests.
- **SC-008**: On repeat launches, the "soon" and outlook sections appear from cache within
  1 second, together with the headline.
- **SC-009**: The privacy disclosure can still state that no user data is collected.

## Assumptions

- **NOAA SWPC data** is published by the US National Weather Service and is in the public domain;
  the app credits it without using NOAA or NWS logos. Its products are open, without
  registration or keys. SWPC changes and retires products without notice (its legacy solar wind
  files were removed in 2026 when SWFO-L1 took over), so every NOAA input can fail on its own
  (FR-020). The products used are listed in the plan's research (R1–R3).
- **Lead time**: solar wind measured at the L1 point reaches Earth in about 30–90 minutes,
  depending on its speed; NOAA publishes a modelled arrival time. The "soon" window is an
  estimate, not a promise.
- **FMI cloud forecast**: the point forecast data set considered in spec 001 (research R5) covers
  the next two nights and is used here at zone positions only.
- **Zones**: the same station zones and representative positions as spec 002.
- **Kp mapping**: Kp is a global index, so its link to what is seen in Finland depends on
  latitude. A fixed mapping per zone, calibrated against recorded data, is accurate enough for a
  two-night outlook; it is not claimed to match fmi.fi.
- **Moon thresholds**: "bright" (above the horizon, at least half illuminated) is a simple,
  explainable starting point. How high the moon is (beyond being above the horizon) and the
  user's direction of view are not modelled.
- **Placement**: the "soon" line and the outlook appear on the main screen below the headline and
  in the details. Widgets show only the headline, with the moon included through the shared rules.
  New widget layouts are out of scope.
- **Out of scope**: forecasts beyond tomorrow night, maps of the auroral oval, all-sky camera
  images, user reports and light pollution.
- **Release**: this feature is planned for a later version than 2.0. It follows the release flow:
  a feature branch, then main, then TestFlight.
