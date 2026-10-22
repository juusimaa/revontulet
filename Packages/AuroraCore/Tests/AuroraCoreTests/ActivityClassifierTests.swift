import Testing
@testable import AuroraCore

@Suite("Activity classifier")
struct ActivityClassifierTests {
    private static let han = Station(id: "HAN", name: "Hankasalmi", latitude: 62.254, longitude: 26.597,
                                     yellowThreshold: 63, redThreshold: 140)
    private static let kev = Station(id: "KEV", name: "Kevo", latitude: 69.756, longitude: 27.007,
                                     yellowThreshold: 55, redThreshold: 165)

    @Test(arguments: [
        (han, 0.0, ActivityLevel.unlikely),
        (han, 62.9, .unlikely),
        (han, 63, .possible),
        (han, 139.9, .possible),
        (han, 140, .probable),
        (han, 500, .probable),
        (kev, 54.9, .unlikely),
        (kev, 55, .possible),
        (kev, 164.9, .possible),
        (kev, 165, .probable),
    ])
    func level(station: Station, r: Double, expected: ActivityLevel) {
        #expect(ActivityClassifier.level(r: r, station: station) == expected)
    }
}
