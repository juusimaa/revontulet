# Contract: FMI Open Data Requests

External interfaces the app consumes. Base URL: `https://opendata.fmi.fi/wfs`. Common query
parameters: `service=WFS&version=2.0.0&request=getFeature`. No API key. Responses are gzipped
XML in the `BsWfs` "simple" format. Licence: CC BY 4.0 (FMI).

Neither request contains any user-derived information.

## 1. Magnetometer (R value input)

```
storedquery_id=fmi::observations::magnetometer::simple
bbox=5,50,40,80
parameters=MAGNX_PT10S_AVG,MAGNY_PT10S_AVG,MAGNZ_PT10S_AVG
starttime=<now − 12 min, floored to 10 s, ISO 8601 UTC>
endtime=<now, ISO 8601 UTC>
```

- Cadence: at most once per 5 minutes while in the foreground, plus manual refresh (debounced to
  once per 30 s).
- Station identification: `gml:pos` matched to the bundled station table within 0.01°.
  Unmatched positions are ignored.

## 2. Cloud cover

```
storedquery_id=fmi::observations::weather::simple
bbox=19,59.5,32,70.1
parameters=TotalCloudCover
starttime=<now − 30 min, ISO 8601 UTC>
endtime=<now, ISO 8601 UTC>
```

- Cadence: at most once per 10 minutes (server `max-age=600`).
- Keep the latest value per position. 0–8 = octas; 9 and `NaN` = unknown.

## Response shape (both)

```xml
<wfs:FeatureCollection ...>
  <wfs:member>
    <BsWfs:BsWfsElement gml:id="...">
      <BsWfs:Location><gml:Point srsName="..."><gml:pos>65.89567 26.40917 </gml:pos></gml:Point></BsWfs:Location>
      <BsWfs:Time>2026-10-22T15:09:00Z</BsWfs:Time>
      <BsWfs:ParameterName>MAGNX_PT10S_AVG</BsWfs:ParameterName>
      <BsWfs:ParameterValue>-42.4</BsWfs:ParameterValue>
    </BsWfs:BsWfsElement>
  </wfs:member>
  ...
</wfs:FeatureCollection>
```

Parsing rules:
- Each `BsWfsElement` → `(latitude, longitude, time, parameter, value)`; `NaN` → missing.
- An `ExceptionReport` root or non-200 status → fetch failure (keep cached result, FR-012).
- Unknown parameters are ignored.

## Failure handling

| Condition | Behaviour |
|---|---|
| No network / timeout (15 s) | Offline state; cached result stays, marked outdated when > 30 min |
| HTTP 4xx/5xx, exception report | Same as offline; retry on next cycle |
| Nearest station has no valid R | Next nearest station with valid R; screen notes the more distant station |
| No station has valid R | No-data state |
| Cloud request fails, magnetometer OK | Chance calculated with clouds = Unknown |
