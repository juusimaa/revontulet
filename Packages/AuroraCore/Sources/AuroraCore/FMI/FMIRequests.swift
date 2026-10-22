import Foundation

/// URLs for the two FMI open data requests (contracts/fmi-open-data.md).
///
/// Both cover a fixed area and contain nothing derived from the user's location.
public enum FMIRequests {
    static let endpoint = "https://opendata.fmi.fi/wfs"

    /// 10-second X/Y/Z magnetometer averages for all stations, 12 minutes back from `now`.
    public static func magnetometer(now: Date) -> URL {
        let end = now.timeIntervalSince1970.rounded(.down)
        let start = ((end - 12 * 60) / 10).rounded(.down) * 10
        return url(
            storedQuery: "fmi::observations::magnetometer::simple",
            bbox: "5,50,40,80",
            parameters: "MAGNX_PT10S_AVG,MAGNY_PT10S_AVG,MAGNZ_PT10S_AVG",
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end)
        )
    }

    /// Total cloud cover from all weather stations in Finland, 30 minutes back from `now`.
    public static func clouds(now: Date) -> URL {
        let end = now.timeIntervalSince1970.rounded(.down)
        return url(
            storedQuery: "fmi::observations::weather::simple",
            bbox: "19,59.5,32,70.1",
            parameters: "TotalCloudCover",
            start: Date(timeIntervalSince1970: end - 30 * 60),
            end: Date(timeIntervalSince1970: end)
        )
    }

    private static func url(storedQuery: String, bbox: String, parameters: String, start: Date, end: Date) -> URL {
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "service", value: "WFS"),
            URLQueryItem(name: "version", value: "2.0.0"),
            URLQueryItem(name: "request", value: "getFeature"),
            URLQueryItem(name: "storedquery_id", value: storedQuery),
            URLQueryItem(name: "bbox", value: bbox),
            URLQueryItem(name: "parameters", value: parameters),
            URLQueryItem(name: "starttime", value: UTCTime.format(start)),
            URLQueryItem(name: "endtime", value: UTCTime.format(end)),
        ]
        return components.url!
    }
}
