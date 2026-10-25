import AuroraCore
import Foundation
import Testing

/// iOS looks up an alert's `title-loc-key` / `loc-key` in the app's Localizable strings in the
/// device language (contracts/push-notification.md), so every key must exist in every language.
@Suite("Alert strings")
struct AlertStringsTests {
    static let languages = ["en", "fi", "sv"]

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"), "no \(language).lproj")
        return try #require(Bundle(path: path))
    }

    @Test(arguments: languages)
    func everyAlertKeyIsTranslated(language: String) throws {
        let bundle = try bundle(language)
        for key in AlertMessage.allKeys {
            let text = bundle.localizedString(forKey: key, value: "\u{0}missing", table: "Localizable")
            #expect(text != "\u{0}missing" && text != key && !text.isEmpty, "\(key) missing in \(language)")
        }
    }

    @Test(arguments: languages)
    func bodiesHaveOneStationPlaceholder(language: String) throws {
        let bundle = try bundle(language)
        for key in AlertMessage.bodyKeys {
            let text = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            let placeholders = text.components(separatedBy: "%@").count - 1
            #expect(placeholders == (key == "alert.body.test" ? 0 : 1), "\(key) in \(language): \(text)")
        }
        for key in AlertMessage.titleKeys {
            #expect(!bundle.localizedString(forKey: key, value: nil, table: "Localizable").contains("%"), "\(key) in \(language)")
        }
    }

    @Test func stationNameIsInserted() throws {
        let format = try bundle("en").localizedString(forKey: "alert.body.goodConditions", value: nil, table: "Localizable")
        #expect(String(format: format, "Oulujärvi") == "Good conditions near Oulujärvi. Look north now.")
    }
}
