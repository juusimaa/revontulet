# Feature Specification: iOS Widgets

**Feature Branch**: `004-ios-widgets`

**Created**: 2026-11-09

**Status**: Draft

**Input**: User description: "iOS widgets. Two sizes: smallest one and the one wide one. Also lock screen widget should be implemented. First UI draft using suitable iOS design skills."

## Overview

Today the user has to open the app to learn whether the aurora is worth a look. This feature
puts the same answer on the Home Screen and the Lock Screen, so a glance at the phone is enough.
The widgets show the headline chance to see (None, Low, Moderate, High, spec 001), the reason,
the place, and how old the data is. They add no new data and no new calculation.

| Surface | Form | Role |
|---|---|---|
| Home Screen, small (square) | Home widget | The answer at a glance: level, reason, place |
| Home Screen, medium (wide) | Home widget | The answer plus the supporting numbers and the "soon" and "tonight" outlook |
| Lock Screen | Circular, rectangular and inline | The answer without unlocking the phone |

A UI draft of all five layouts is in [ui-draft/widgets.html](ui-draft/widgets.html) (open in a
browser). It is a direction to build from, not pixel-final; the build follows the `ios-ui-craft`
skill's screenshot-driven iteration (constitution VI).

## UI Draft Direction

- **Point of view**: the widget is a window to the same night sky as the app. The Home Screen
  widgets use the app's dark sky gradient with the app's aurora curtains, whose strength follows
  the level, so the level is read from colour and light before the text is read.
- **Sky artwork**: the Home Screen widgets show a still frame of the app's own aurora curtains
  (the main screen's sky), not a generic glow. Curtain height and brightness follow the level:
  none for None, a faint low band for Low, taller for Moderate, tall with magenta for High. The
  lower part of the widget is darkened so text stays readable, and stale data dims the sky. The curtains are softened with a medium blur (5 px at
  small-widget size, as in the draft) so they stay a calm backdrop and the text stays the
  clearest element; sharper curtains looked like an equalizer and competed with the text.
- **Glyph**: the aurora mark (a wavy curtain with hanging rays) is the one glyph used in the top
  line, the Lock Screen widgets and the circular gauge.
- **Hierarchy**: level word first and largest, reason second, place and data age last. One idea
  per widget; nothing that needs a second look.
- **Colour**: one dominant (the sky) with the aurora green/magenta accent carrying the level.
  Never purple-on-indigo gradients; magenta only for High, as in the app.
- **Type**: system type with a heavy level word and a clear weight step down for the reason and
  place; Dynamic Type respected; numbers use tabular figures.
- **Recognition**: no app name on the widget. The top line of the Home Screen widgets starts
  with the aurora glyph, tinted by the level; the circular Lock Screen widget is the glyph inside
  the gauge; the rectangular and inline ones carry the glyph or "Aurora".
- **Lock Screen**: monochrome by system rule. The level is carried by a gauge fill and a word,
  never by colour alone.
- **States**: designed placeholder, stale, offline-with-cache, no place yet and no data, each
  distinct (see requirements).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Glance at the chance on the Home Screen (Priority: P1)

On a dark evening the user unlocks the phone and, on the Home Screen, sees the small widget:
"Moderate – clear sky", the place name and "12 min ago". They decide to head out without opening
the app. A medium widget shows the same plus the R value, the nearest station, and the outlook
for the next hour and tonight.

**Why this priority**: This is the feature. The small widget alone is a complete, valuable MVP.

**Independent Test**: With the app having produced at least one result, add the small widget and
verify it shows the level, reason, place and data age matching the app's main screen; add the
medium widget and verify the extra detail matches the app's details and outlook.

**Acceptance Scenarios**:

1. **Given** the app has a current result, **When** the user adds the small widget, **Then** it
   shows the chance level (word and colour), the limiting factor or "good conditions" reason, the
   place name and the age of the data.
2. **Given** the same state, **When** the user adds the medium widget, **Then** it shows the same
   headline and additionally the R value with its station, and the "soon" and "tonight" outlook
   where the app has them.
3. **Given** the widget is shown, **When** the user taps it, **Then** the app opens on its main
   screen.
4. **Given** the app and the widget show the same place, **When** the data is the same, **Then**
   the widget and the app agree on the level and reason.

---

### User Story 2 - See the chance on the Lock Screen (Priority: P2)

The user adds the rectangular widget to the Lock Screen: a gauge and "Moderate · clear sky".
Beside the clock they add the circular widget, and in the line above the clock the inline one:
"Aurora: Moderate". Waking the phone in the yard answers the question.

**Why this priority**: Fast and valuable, but the Home Screen widgets already deliver the core
value; the Lock Screen needs its own monochrome layouts and states.

**Independent Test**: Add each Lock Screen variant, lock the phone, and verify it reads clearly
in light, dark and tinted Lock Screens and under the system's reduced-luminance (always-on) look.

**Acceptance Scenarios**:

1. **Given** a current result, **When** the user adds the circular widget, **Then** it shows the aurora
   glyph inside a gauge filled to the level (four steps), with no word in the ring.
2. **Given** a current result, **When** the user adds the rectangular widget, **Then** it shows
   the level, the reason and the data age in at most three short lines.
3. **Given** a current result, **When** the user adds the inline widget, **Then** it shows one
   line with the app name or icon, the level and, if it fits, the place.
4. **Given** any Lock Screen widget, **When** the user taps it, **Then** the phone asks to unlock
   and then opens the app.

---

### User Story 3 - Widgets stay honest when data is old or missing (Priority: P2)

The user is in the countryside with poor coverage. The widget still shows the last known result,
clearly marked as old, and never a blank or misleading tile. A user who has not opened the app
yet sees a clear prompt instead of a fake level.

**Why this priority**: Constitution VI requires every surface to show data age and to design
loading, offline, stale and empty states.

**Independent Test**: Cut the network, let the widget age past its freshness limit, and verify
the stale look; add a widget on a fresh install and verify the "open the app" state.

**Acceptance Scenarios**:

1. **Given** the latest data is older than the freshness limit, **When** the widget is shown,
   **Then** it shows the last level dimmed, with "Old data" and its age, and no claim that it is
   current.
2. **Given** the app has never produced a result, **When** the widget is shown, **Then** it shows
   "Open Revontulet to choose a place" and no level.
3. **Given** the widget is in the widget gallery, **When** it is previewed, **Then** it shows a
   plausible sample (clearly a sample), not a blank tile.
4. **Given** the nearest station has no valid R value, **When** the widget is shown, **Then** it
   shows the same "no data" wording as the app, not a level.

---

### User Story 4 - Widgets keep up with the sky, even when the app is closed (Priority: P2)

During an active evening the activity changes within minutes, and the user may not have opened
the app for days. The widgets refresh themselves whenever the system allows, so they keep
showing current data without the user opening anything. The refresh rhythm is tighter at night
in the aurora season and sparse in daylight, and never drains the battery.

**Why this priority**: Without self-refresh the widgets only update when the user opens the app,
which defeats their purpose.

**Independent Test**: Install a widget, do not open the app for an evening, and verify the
widget's data time advances on its own and its age label never claims fresher data than it has.
Enable Low Power Mode and verify the widgets fall back to the stale look when data ages.

**Acceptance Scenarios**:

1. **Given** the app has not been opened for hours, **When** new FMI data is published, **Then**
   the widget updates at the system's next refresh opportunity.
2. **Given** a widget refresh finds no network, **When** it ends, **Then** the last result is
   kept untouched and the widget does not claim it is newer.
3. **Given** the user has not chosen a place yet, **When** the system refreshes the widget,
   **Then** nothing is fetched.
4. **Given** the user opens the app and gets a new result, **When** they return to the Home
   Screen, **Then** the widgets show that result without waiting for the next scheduled refresh.
5. **Given** the user changes the place in the app, **When** they return to the Home Screen,
   **Then** the widgets show the new place.

---

### Edge Cases

- Location access is denied and the user picked a municipality by hand: widgets use that place.
- The user is outside Finland or too far from any station: the widget shows the app's
  out-of-coverage wording, not a level.
- Cloud cover is unknown: the level is shown as in the app, with the "clouds not included" note
  where space allows (medium) and omitted where it does not (small, Lock Screen).
- Daytime ("too light"): the widget shows the level None with the reason, in a calm daytime look,
  not an alarming one.
- Very long municipality names and larger Dynamic Type sizes: text truncates or scales without
  overlapping; the level and reason always stay visible.
- Finnish, Swedish and English strings differ in length; none may clip the level word.
- Always-on / reduced-luminance and tinted Home Screen modes: the level stays readable without
  relying on colour.
- Reduce Motion: widgets are static by nature; any decorative glow must not look different in
  meaning when animation is off.
- The user removes all widgets: nothing about widgets continues to run or fetch.
- Several widgets of different sizes refresh at the same moment: the data is fetched at most
  once and shared through the cache.
- A widget refresh is cut short or fails: the previous cached result stays whole.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST offer a small and a medium Home Screen widget and circular,
  rectangular and inline Lock Screen widgets, all selectable from the system widget gallery.
- **FR-002**: Every widget MUST show the headline chance level using the same four levels, rules
  and wording as the app's main screen, and MUST NOT introduce its own calculation.
- **FR-003**: The small widget MUST show the level, the reason (limiting factor or good
  conditions), the place name and the age of the data.
- **FR-004**: The medium widget MUST show everything the small one does plus the R value with
  its station and, when the app has them, the "soon" and "tonight" outlook.
- **FR-005**: The circular Lock Screen widget MUST show the level as a four-step gauge around the aurora
  glyph (no word in the ring); the rectangular MUST show level, reason and data age; the inline MUST fit on one
  line and show the level.
- **FR-006**: The level MUST NOT be communicated by colour alone on any widget; a word or gauge
  position MUST always carry it.
- **FR-007**: Data age MUST be visible on every widget except the inline one, where it MUST
  instead be reflected by the stale wording when data is old.
- **FR-008**: When the data is older than the freshness limit (the same limit the app uses for
  "not current"), the widget MUST show the last result dimmed and marked as old, never as
  current.
- **FR-009**: Every widget MUST have designed placeholder, gallery-sample, no-place-yet,
  no-data/out-of-coverage and offline-with-cache states.
- **FR-010**: Tapping any widget MUST open the app on its main screen.
- **FR-011**: Widgets MUST show the place the app currently uses (current location or manually
  chosen municipality) and MUST update when the user changes it in the app.
- **FR-012**: Widgets MUST refresh on the system's timeline schedule, with a refresh rhythm that
  is tighter when activity can matter (dark hours, aurora season) and sparse otherwise, and MUST
  also refresh when the app produces a new result.
- **FR-013**: Widgets MUST work with no network by showing the last cached result.
- **FR-014**: Widgets MUST NOT start location tracking, request location access, send precise
  coordinates anywhere, collect analytics or use any account; whatever they fetch MUST be the
  same open data, with the same limits, the app uses (constitution I, II).
- **FR-015**: All widget text MUST be available in Finnish, Swedish and English, follow the
  system language, and support Dynamic Type where the widget family allows it.
- **FR-016**: Every widget MUST have a VoiceOver description that reads the level, reason, place
  and data age as one sentence, and MUST be legible in Dark Mode, light Home Screen, tinted and
  Lock Screen vibrancy modes.
- **FR-017**: Widgets MUST use the app's night-sky visual language (sky gradient, aurora glow
  strength by level) on the Home Screen and system-native monochrome styling on the Lock Screen,
  with system glass and materials where the system supplies them, not custom imitations.
- **FR-018**: The App Store privacy label MUST still be able to state "Data Not Collected".
- **FR-019**: Each widget refresh MUST fetch the same open data as the app for the stored
  place, apply the shared chance rules, and store the result in the cache the app also reads, so
  widgets stay current without the app being opened.
- **FR-020**: A widget refresh MUST first check the shared cache and MUST NOT fetch when the data
  there is still fresh, so that several widgets reloading together make no more requests than
  the data updates (constitution I). If a refresh fails or is cut short, the previous result
  MUST stay intact.
- **FR-021**: Widgets MUST read the place from storage shared with the app on the device, and
  MUST NOT fetch anything when no place has been chosen.
- **FR-022**: When fresh data cannot be fetched (no network, Low Power Mode, throttled refresh),
  widgets MUST show the stale state rather than pretend to be current.
- **FR-023**: Every widget MUST be recognisable as Revontulet without printing the app name: the
  Home Screen widgets by the aurora glyph in the top line, the circular Lock Screen widget by the
  glyph inside the gauge, the rectangular and inline ones by the glyph or the word "Aurora".
- **FR-024**: The Home Screen widgets MUST draw a still version of the app's aurora artwork
  whose strength follows the level and which is softly blurred so it never competes with the text,
  with the text area kept dark enough for the level word and
  reason to stay readable, and MUST dim the artwork when the data is stale. The artwork MUST NOT
  be the only carrier of the level (FR-006) and MUST remain legible when the system tints or
  desaturates widgets.

### Key Entities *(include if feature involves data)*

- **Widget snapshot**: what a widget draws at one moment: level, reason, place name, station and
  R value, outlook lines, the time the data is from, and whether it counts as stale. Derived from
  the app's existing result and outlook; shared between the app and the widgets on the device
  only.
- **Selected place**: the place the app currently uses; the widgets follow it and have no place
  setting of their own in this version.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can read the current chance level from the Home Screen or Lock Screen in
  under 2 seconds without opening the app (checked with 5 people).
- **SC-002**: In 100% of checked states the widget level and reason match the main screen for
  the same data and place.
- **SC-003**: After a new result in the app, the widgets show it within 5 seconds of the user
  returning to the Home Screen.
- **SC-004**: With no network, every widget shows the last result with its age, never a blank
  or broken tile, in all five layouts.
- **SC-005**: Each layout passes a review at the largest accessibility text size, in the three
  languages, with no clipped level word or overlap.
- **SC-006**: Widget refreshes stay within the system's budget: the app is not listed among high
  battery users in a normal week with widgets installed.
- **SC-007**: The privacy label still states "Data Not Collected" and no new data leaves the
  device.
- **SC-008**: On a normal evening of use, a widget on a phone whose app was not opened that day
  shows data no older than 1 hour for at least 80% of checks made between dusk and midnight in
  the aurora season.

## Assumptions

- The widgets follow the app's current place and offer no configuration in this version;
  per-widget place choice is a possible later feature.
- "Smallest" means the small Home Screen widget and "wide" means the medium one; the large and
  extra-large sizes and StandBy-specific designs are out of scope (they are not blocked).
- Alerts are unaffected; widgets are read-only and have no controls beyond opening the app.
- Widgets show data the same way the app does, including the outlook; if the outlook is
  unavailable the medium widget shows the headline and detail only.
- The system decides when widgets actually refresh; the widget can only suggest a rhythm. The
  refresh is best effort: iOS may run it rarely, and more rarely in Low Power Mode, so the stale
  state remains a first-class state.
- There is no separate background refresh in the app for the widgets: the widgets fetch their own
  data when the system asks them to refresh. Alerts keep working through the alert backend as in
  spec 002 and are unaffected.
- Widgets use the stored place and never ask for a new location fix; a user who has moved far
  since the last time they opened the app sees the old place until they open it.
- The widgets reuse the core's chance rules and the cached result; sharing that between the app
  and the widgets stays on the device (Principle III keeps domain logic in AuroraCore).
- Live Activities, Control Center controls and interactive widget buttons are out of scope.
- Android widgets are out of scope.
