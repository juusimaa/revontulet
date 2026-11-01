# Revontulet Privacy Policy

*Last updated: 30 October 2026*

Revontulet does not collect or share personal data. The only exception is the optional aurora
alerts: if you turn them on, a minimum of data is stored on the developer's alert service so it
can notify you. This policy explains what the app does with your location, what it sends over
the network, and what alerts store.

## Your location

If you allow location access, Revontulet uses your position to find your municipality and the
nearest measurement station, and to work out whether it is dark where you are. This happens only
on your device. Your location is never sent to the developer, to the Finnish Meteorological
Institute (FMI) or to anyone else.

Aurora alerts use only a coarse area derived on your device (see below); your position itself
is never sent.

The app uses location only while it is open. You can turn location access off at any time in
Settings and choose a municipality by hand instead.

## Network requests

The app downloads magnetometer and cloud cover observations, and a cloud cover forecast, from
FMI's open data service (opendata.fmi.fi). Every observation request covers the same fixed area
for all of Finland, and the forecast request asks for all ten alert areas at once, so no request
contains anything about you or your location.

For the "soon" line and the outlook for tonight and tomorrow night, the app downloads solar wind
data, the Kp forecast and geomagnetic storm watches from the NOAA Space Weather Prediction Center
(services.swpc.noaa.gov) in the United States. These requests are fixed addresses, identical for
every user, and carry nothing about you, your location or your area.

As with any internet request, FMI's and NOAA's servers see your IP address; their own privacy
notices cover how they handle them.

If you turn on aurora alerts, the app also talks to the developer's alert service (see below).
The app makes no other network requests. The alert service itself does not use NOAA data.

## Aurora alerts (optional)

Aurora alerts are **off by default**. Nothing is sent to the alert service until you turn them
on in the app.

**What is stored.** When alerts are on, the alert service stores only:

- the anonymous notification address (push token) that Apple gives the app for this iPhone, and
  whether it belongs to a development or a production build of the app
- your alert area: one of ten areas in Finland, each the area around one FMI measurement
  station, worked out on your device from your location or the municipality you chose
- the alert level you chose (Moderate or High)
- the day the app last confirmed the registration (the date only, not the time)

**Why.** To send you a notification when the chance to see the aurora in your area reaches the
level you chose. Nothing else is done with it.

**What is not stored.** No IP addresses, no position, no device or app details, no language and
no name or account. The alert service keeps no request logs, and the web server in front of it
keeps no access logs. Notifications are written in your language on your iPhone, so the service
never needs to know it.

**Where.** On the developer's own alert service, hosted by UpCloud in Helsinki, Finland.
Notifications are delivered through Apple's push notification service.

**How long.** The registration is deleted:

- when you turn alerts off in the app,
- when Apple reports that the notification address is no longer valid (for example after you
  delete the app), or
- when the app has not confirmed it for 180 days. The app confirms it at most once a day when
  you open it.

The alert service keeps one backup copy of its database, overwritten every night, so a deleted
registration can remain in the backup for at most about one day.

**How to delete it.** Turn alerts off in the app. If you turn off notifications for Revontulet in
iOS Settings, the app deletes the registration the next time you open it. If you delete the app,
the registration is removed when Apple reports the address as invalid, or at the latest after
180 days.

The data is not shared with anyone.

## Data stored on your device

- **The last result**, including the position it was calculated for, so it can be shown
  immediately the next time you open the app. It is excluded from device backups.
- **The last forecast**: the downloaded solar wind, Kp forecast, storm watches and cloud forecast,
  with the place they were last shown for, so the outlook can be shown immediately and offline.
  It is excluded from device backups.
- **Your place choice**: whether you use your current location or a municipality you picked.
- **Your alert settings**, if you have used aurora alerts: whether they are on, the alert level,
  the alert area and the notification address.

Deleting the app removes all of these.

## What the app does not do

- No accounts or sign-in
- No location sent anywhere: aurora alerts send only a coarse area, and only if you turn them on
- No analytics, crash reporting or advertising
- No tracking, and no third-party code that tracks you
- No data sold or shared with anyone

## Children

The app collects no data from anyone, including children, beyond the optional aurora alert
registration described above, which contains nothing that identifies a person.

## Changes

If this policy changes, the new version will be published at this address with a new date.

## Contact

Questions about privacy: open an issue at
[github.com/juusimaa/revontulet/issues](https://github.com/juusimaa/revontulet/issues).
