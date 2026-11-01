import Foundation

/// NOAA Space Weather Prediction Center products (specs/003-aurora-outlook/contracts/noaa-data.md).
///
/// Fixed URLs without parameters: every request is the same for every user (FR-018).
public enum NOAARequests {
    /// Solar wind observed at L1 in the last hour, with SWPC's modelled arrival time at Earth.
    public static let propagatedSolarWind = URL(string: "https://services.swpc.noaa.gov/products/geospace/propagated-solar-wind-1-hour.json")!
    /// 3-hour Kp blocks: about a week observed and estimated, about 2.5 days predicted.
    public static let kpForecast = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json")!
    /// The last 30 days of alerts, watches and warnings; storm watches are parsed from these.
    public static let alerts = URL(string: "https://services.swpc.noaa.gov/products/alerts.json")!
}
