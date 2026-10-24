# Feature Specification: Aurora Alerts

**Feature Branch**: `002-aurora-alerts`

**Created**: 2026-10-24

**Status**: Draft

**Input**: User description: "Aurora alerts: opt-in push notifications when the aurora chance in the user's coarse zone reaches the user's chosen threshold. Design B: the app registers an APNs device token plus one coarse zone (one per FMI magnetometer station area) and a threshold (Moderate or High) with a minimal backend; the backend stores nothing else. Off by default; enabling alerts is the moment of registration; disabling deletes the registration. Backend: small Swift service reusing the portable AuroraCore package on Linux; every 5–10 minutes fetches FMI open data, computes R value and level per zone (geomagnetic activity, darkness, cloud cover per zone), sends APNs pushes to tokens in zones crossing their threshold, with a cooldown to avoid repeat alerts; missed alerts during downtime are not replayed. Notification text is localized on the device via loc-key/loc-args (Finnish, Swedish, English) so the server never knows the user's language. Endpoints: register/update and delete; tokens APNs reports invalid (410) are removed. The app, widgets and map never depend on the backend; if it is down only alerts stop, and registration retries quietly. Hosting: existing UpCloud server in Helsinki (1 CPU, 2 GB, ~880 MB available), as its own Docker Compose project with a 150 MB memory limit on the shared external `edge` Docker network behind the existing Caddy (site file in /opt/edge/sites, without the access_log import so no IP addresses are logged); image built in CI and pushed to GHCR, never built on the server; APNs .p8 key as a Docker secret; SQLite on a host volume with backups; heartbeat monitoring so silent failure is noticed. Privacy: constitution requires opt-in backend with minimum data (coarse region, push token) and a spec reviewed against Principle II; update docs/privacy.md to name UpCloud and the stored data; reassess the App Store privacy label (coarse location may count as collected, not linked, App Functionality). Part of the v2.0 milestone with Widgets (#1) and Map view (#2)."

## Clarifications

### Session 2026-10-24

- Q: How is the user's alert zone chosen? → A: It follows the app's place automatically (current
  location or chosen municipality) and is updated when the app is used in a new zone.
- Q: How should alerts behave at night? → A: Normal priority at any hour; iOS Focus and Sleep
  settings decide whether they are shown. No time-sensitive alerts and no in-app quiet hours.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Get told when the aurora is visible near me (Priority: P1)

The user does not want to keep checking the app every evening. They turn on aurora alerts and
choose how strong the chance must be (Moderate or High). Later, when the chance to see the aurora
in their area reaches that level, a notification tells them, in their own language, how good the
chance is and why (e.g. "High chance of aurora near Oulujärvi – clear sky"). Tapping it opens the
app's main screen with the current result.

**Why this priority**: This is the feature. Aurora displays often last less than an hour, and
an alert is the only way to catch one without watching the app.

**Independent Test**: Turn alerts on with threshold Moderate in a zone, then feed the alert
service recorded FMI data in which that zone's chance rises from Low to Moderate on a dark, clear
night; verify that one notification arrives on the device, in the device language, naming the
level and the reason, and that tapping it opens the main screen.

**Acceptance Scenarios**:

1. **Given** alerts are off (the default), **When** the user turns them on and allows
   notifications, **Then** alerts are on for the user's zone with the chosen threshold, and the
   settings show the zone and threshold.
2. **Given** alerts are on with threshold Moderate, **When** the chance to see in the user's zone
   reaches Moderate or High, **Then** the user receives one notification stating the level, the
   zone and the main reason.
3. **Given** alerts are on with threshold High, **When** the chance in the zone reaches only
   Moderate, **Then** no notification is sent.
4. **Given** high geomagnetic activity in the zone, **When** it is daytime or the sky is overcast
   there so the chance stays below the threshold, **Then** no notification is sent.
5. **Given** an alert was sent, **When** the chance stays at or above the threshold, **Then** no
   repeat notification is sent for that same level (see FR-008 for repeat rules).
6. **Given** a user with threshold Moderate received a Moderate alert, **When** the chance in the
   zone rises to High, **Then** one further notification is sent for High.
7. **Given** the user receives an alert, **When** they tap it, **Then** the app opens on the main
   screen and shows the current result for the user's place, which may differ from the zone
   result in the notification.

---

### User Story 2 - Stay in control and private (Priority: P2)

The user can see at any time whether alerts are on, for which zone and at which threshold. They
can change the threshold or turn alerts off, and turning them off removes everything the alert
service knew about the device. The app explains, before turning alerts on, what is sent and why.

**Why this priority**: Alerts are the app's first feature that sends anything about the user to a
server of its own; the project's privacy principle makes control and transparency a condition for
shipping it.

**Independent Test**: Turn alerts on, change the threshold, then turn alerts off; verify after
each step what the alert service stores for the device (the registration exists with the new
values, then no longer exists).

**Acceptance Scenarios**:

1. **Given** alerts are off, **When** the user opens the alert settings, **Then** the app explains
   in plain language that turning alerts on sends an anonymous notification address and the user's
   coarse zone (not their location) to the developer's alert service in Finland.
2. **Given** alerts are on, **When** the user changes the threshold, **Then** the registration is
   updated and no notification is sent because of the change itself.
3. **Given** alerts are on, **When** the user turns them off, **Then** the registration is
   deleted from the alert service and no further alerts arrive.
4. **Given** the user has denied notification permission in iOS Settings, **When** they try to
   turn alerts on, **Then** the app explains that notifications are off and offers a way to open
   Settings; alerts are not registered.
5. **Given** the device is offline or the alert service is unreachable when the user turns alerts
   on, off or changes them, **Then** the change is kept on the device, retried automatically
   without error dialogs, and the settings show that the change is not yet confirmed.

---

### User Story 3 - Know that alerts work (Priority: P3)

Strong aurora nights are rare, so a user may go weeks without an alert and wonder whether the
feature works. They can send themselves a test notification, and the settings show when the
alert service last confirmed their registration.

**Why this priority**: Builds trust in a feature that is silent most of the time, but alerts work
without it.

**Independent Test**: With alerts on, request a test notification and verify that it arrives
within one minute and is clearly marked as a test.

**Acceptance Scenarios**:

1. **Given** alerts are on and confirmed, **When** the user requests a test notification, **Then**
   a notification clearly marked as a test arrives within one minute.
2. **Given** the user has requested several test notifications in a short time, **When** they
   request another, **Then** the request is refused with an explanation and a time when they can
   try again.

---

### Edge Cases

- **Summer and daylight**: in the months when it never gets dark enough in a zone, no alerts can
  be sent there; the alert settings say so ("Alerts resume when nights get dark again") rather
  than appearing broken.
- **The user moves to another zone**: the zone is updated as described in FR-004; alerts are
  never sent for a zone the user did not have at the time.
- **Station outage**: if a zone's station has no recent data, the zone's activity is taken from
  the next nearest station with recent data, as the app does (spec 001, FR-005), so alerts in that
  zone continue.
- **Cloud data unavailable**: the zone's chance is based on activity and darkness only; the
  notification says cloud cover is unknown.
- **Alert service down**: no alerts are sent during the outage, and missed alerts are not sent
  afterwards because they would be out of date; the app, widgets and map keep working normally.
- **FMI data unavailable to the alert service**: no alerts are sent; nothing is shown to users.
- **The level flickers around the threshold**: repeat rules (FR-008) prevent a notification each
  time it crosses back up.
- **App deleted**: the registration becomes invalid and is removed by the alert service the next
  time it tries to send, or by the retention rule (FR-014).
- **Notifications turned off in iOS Settings**: the notification system does not report this, so
  the app checks permission each time it is opened; if alerts are on and notifications are off,
  it deletes the registration and shows alerts as off with a way to open Settings.
- **The user is outside Finland**: zones cover Finland only; with current location outside
  Finland, alerts follow the last zone the user had in Finland, or cannot be turned on if there
  has never been one, with an explanation.
- **Several devices**: each device has its own independent registration.
- **Device language changes after registration**: notifications follow the new device language,
  since the text is chosen on the device.

## Requirements *(mandatory)*

### Functional Requirements

#### In the app

- **FR-001**: Alerts MUST be off by default. Nothing MUST be sent to the alert service until the
  user turns alerts on.
- **FR-002**: Before alerts are turned on for the first time, the app MUST explain what is sent
  (an anonymous notification address, the coarse zone and the threshold), where it is processed
  (the developer's alert service in Finland) and that turning alerts off deletes it, with a link
  to the privacy policy.
- **FR-003**: The user MUST be able to choose the threshold: Moderate (Moderate or High) or High
  (High only). The default threshold is High.
- **FR-004**: The user's zone MUST follow the app's place automatically: the zone of the current
  location, or of the chosen municipality when the user has picked one. When the app determines
  a different zone during normal use, it MUST update the registration. The zone MUST be
  determined on the device, and only the new zone MUST be sent. Alerts MUST NOT cause any
  location use beyond what the app already does while open, and in particular no background
  location tracking.
- **FR-005**: The alert settings MUST show whether alerts are on, the zone (by its station name),
  the threshold, and whether the latest change has been confirmed by the alert service.
- **FR-006**: Turning alerts off MUST delete the registration from the alert service. If the
  service cannot be reached, the app MUST keep retrying until the deletion is confirmed, and
  MUST NOT show alerts as on in the meantime.
- **FR-007**: App features other than alerts MUST NOT depend on the alert service. The main screen,
  widgets and map MUST work identically whether or not the service is reachable, and failures to
  reach it MUST NOT produce error dialogs outside the alert settings.

#### Alerts

- **FR-008**: A zone's chance to see MUST be computed with the same rules the app uses (spec 001,
  FR-001 to FR-001d) at the zone's representative position, and checked at least as often as new
  FMI magnetometer data is published. A notification MUST be sent to every registration in the
  zone when the zone's chance reaches its threshold. After an alert for a level, no further alert
  for the same level and zone MUST be sent until the chance has stayed below that level for at
  least 60 minutes. A rise from Moderate to High MUST trigger one further alert for registrations
  with threshold Moderate. A registration MUST NOT receive more than 3 alerts per night from
  its zone. Repeat and nightly-cap state MUST be kept per zone, not per device.
- **FR-009**: Alerts MUST NOT be sent late: if the conditions that triggered an alert are older
  than 20 minutes when it would be sent (e.g. after an outage), it MUST be dropped.
- **FR-010**: The notification MUST state the chance level, the zone's station name and the main
  reason (e.g. "clear sky", "cloud cover unknown"), in Finnish, Swedish or English following the
  device language, with English as the fallback. The alert service MUST NOT need to know the
  user's language.
- **FR-011**: Alerts MUST be delivered at any hour with normal priority, so that the user's iOS
  Focus, Sleep and notification settings decide whether and how they are shown. Alerts MUST NOT
  be marked time-sensitive or critical, and the app MUST NOT offer its own quiet hours.
- **FR-012**: The user MUST be able to request a test notification, limited to 3 per hour per
  registration.

#### Alert service

- **FR-013**: For each registration, the alert service MUST store only: the notification
  address (the push token), the zone, the threshold, and the time the registration was last confirmed. It MUST NOT
  store or log IP addresses, device or app details, language, or anything derived from the user's
  location beyond the zone.
- **FR-014**: The alert service MUST delete a registration when the user turns alerts off, when
  the notification system reports the address as invalid, or when the app has not re-confirmed it
  for 180 days. The app MUST re-confirm an active registration at most once a day when it is
  opened.
- **FR-015**: The alert service MUST be hosted in Finland or elsewhere in the EU, by a provider
  named in the privacy policy, and MUST NOT share data with anyone.
- **FR-016**: The alert service MUST use only FMI open data and the same data sets as the app
  (Principle I), MUST respect FMI usage limits, and MUST fetch data for all zones together rather
  than per user.
- **FR-017**: The alert service MUST reject malformed registrations and limit how often a single
  client can register, update or request test notifications, so it cannot be used to flood users
  or itself.
- **FR-018**: The developer MUST be notified within 30 minutes when the alert service stops
  checking conditions or stops being able to send notifications.

#### Privacy and disclosure

- **FR-019**: The privacy policy MUST be updated before release to describe alerts: what is
  stored, why, where (hosting provider and country), for how long, and how to delete it.
- **FR-020**: The App Store privacy label MUST be reassessed for this feature and the outcome
  recorded in this spec's Privacy Review before release.

### Key Entities

- **Alert zone**: A coarse area of Finland, one per FMI magnetometer station used by the app: the
  area where that station is the nearest. Has the station's name and a representative position
  used for darkness and cloud cover.
- **Zone condition**: A zone's current chance to see (level, limiting factor, reason) and the
  time of the data it is based on.
- **Alert registration**: One device's request to be alerted: an anonymous notification address,
  a zone, a threshold and the time it was last confirmed. Not linked to any person or account.
- **Alert state**: For each zone, which levels have been alerted and when, and how many alerts
  were sent tonight, used for the repeat rules and the nightly cap; kept per zone, never per
  device.
- **Alert notification**: The message delivered to a device: level, zone station name and reason
  as identifiers that the device turns into text in its own language.

## Privacy Review (Principle II)

- **Opt-in**: alerts are off by default; nothing is sent until the user turns them on (FR-001,
  FR-002).
- **Minimum data**: a push token, one zone out of about ten, a threshold and a confirmation time
  (FR-013). The zone is the "coarse region" the constitution allows; precise coordinates and
  the municipality never leave the device. Because the zone follows the user's place (FR-004),
  the service learns about zone changes, i.e. coarse movement between station areas, while the
  app is in use. It keeps only the current zone, never a history of zones.
- **No language, IP or device data** is stored or logged (FR-010, FR-013).
- **Deletion**: turning alerts off deletes the registration; invalid and abandoned registrations
  are deleted automatically (FR-006, FR-014).
- **App Store label**: "Data Not Collected" no longer applies: Apple counts data stored on a
  server beyond the request as collected, so the zone is collected coarse location and the stored
  push token is best declared as a device ID. Proposed label: **Coarse Location** and **Device
  ID**, both **App Functionality**, **not used for tracking**, **not linked to the user** (no
  accounts; nothing ties the token to a person). "Linked to You" remains the conservative
  alternative (research R11). This deviation from the constitution's default
  label is justified by the alerts' purpose and the opt-in. The final decision is recorded here
  before release (FR-020).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: While the alert service is running, at least 95% of alerts reach the device within
  15 minutes of FMI publishing the data that raised the zone's chance to the threshold.
- **SC-002**: For a set of at least 20 reference nights, at least 3 of them recorded from FMI data
  and the rest synthetic sequences of zone conditions, alerts are sent exactly when
  the zone's chance reaches the threshold under the documented rules, in 100% of cases, and never
  in daylight or under the threshold.
- **SC-003**: No registration receives more than 3 alerts in one night from its zone.
- **SC-004**: A user can turn alerts on, including the explanation and the notification
  permission prompt, in under 30 seconds.
- **SC-005**: After the user turns alerts off while online, the alert service no longer holds the
  registration within 1 minute.
- **SC-006**: An inspection of everything the alert service stores and logs finds nothing beyond
  the data listed in FR-013.
- **SC-007**: With the alert service unreachable, 100% of the main screen, widget and map
  acceptance scenarios still pass.
- **SC-008**: Any outage of the alert service longer than 30 minutes is noticed by the developer
  within 30 minutes of it starting.

## Assumptions

- **Zones**: one per FMI magnetometer station the app uses (10 stations, spec 001); the zone of a
  place is that of its nearest station. Zone membership is decided on the device.
- **Chance rules**: the zone's chance uses exactly the app's rules from spec 001, applied at the
  zone's representative position; the user's own place can still differ (e.g. local clouds),
  which is why tapping the notification shows the app's own result.
- **Representative position**: the station's position, unless planning finds that a zone centre
  gives better darkness and cloud results.
- **Zone names** are station names as FMI publishes them; southern Finland's zone is Tartu
  (Estonia), matching the station the main screen already shows there.
- **One zone per device** for this feature; alerts for several places (e.g. a summer cottage)
  belong with a future saved-places feature.
- **Delivery**: notifications use Apple's push notification service; delivery timing is
  ultimately up to Apple and iOS, and SC-001 is measured while the device is online.
- **No backend existed before**: this feature introduces the first backend. The constitution's
  Technology & Platform Constraints said "Backend: none"; constitution v1.1.0 (2026-10-24)
  replaces that with rules for one opt-in alert backend, which this spec follows.
- **Hosting and technology decisions already made** (inputs to the plan, not requirements): the
  service reuses the shared core package on Linux; it runs as its own container on the existing
  UpCloud server in Helsinki behind the existing reverse proxy, with a memory limit, built in CI
  and pulled from the container registry, with request logging disabled for its address, the
  push signing key kept as a secret, a small local database with backups, and heartbeat
  monitoring.
- **Release**: alerts ship in v2.0 together with Widgets (#1) and Map view (#2); none depends on
  the others.
