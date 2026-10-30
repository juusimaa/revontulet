import Foundation
import Testing
@testable import AuroraCore

@Suite("NOAA requests (contracts/noaa-data.md)")
struct NOAARequestsTests {
    @Test func fixedURLs() {
        #expect(NOAARequests.propagatedSolarWind.absoluteString
            == "https://services.swpc.noaa.gov/products/geospace/propagated-solar-wind-1-hour.json")
        #expect(NOAARequests.kpForecast.absoluteString
            == "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json")
        #expect(NOAARequests.alerts.absoluteString == "https://services.swpc.noaa.gov/products/alerts.json")
    }

    /// FR-018: nothing in the request depends on the user, the place or the zone.
    @Test(arguments: [NOAARequests.propagatedSolarWind, NOAARequests.kpForecast, NOAARequests.alerts])
    func noQueryItems(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems == nil)
        #expect(components?.fragment == nil)
    }
}
