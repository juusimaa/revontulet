import Testing
@testable import AlertServer

@Suite("Configuration")
struct ConfigurationTests {
    private let required = [
        "APNS_KEY_ID": "ABC123DEFG",
        "APNS_TEAM_ID": "TEAM123456",
        "APNS_KEY_PATH": "/run/secrets/apns_key",
        "APNS_TOPIC": "fi.juusimaa.revontulet",
        "DATABASE_PATH": "/data/alerts.db",
    ]

    @Test func readsRequiredValuesAndDefaults() throws {
        let configuration = try Configuration(environment: required)

        #expect(configuration.apnsKeyID == "ABC123DEFG")
        #expect(configuration.apnsTeamID == "TEAM123456")
        #expect(configuration.apnsKeyPath == "/run/secrets/apns_key")
        #expect(configuration.apnsTopic == "fi.juusimaa.revontulet")
        #expect(configuration.databasePath == "/data/alerts.db")
        #expect(configuration.apnsEnvironment == .production)
        #expect(configuration.healthcheckPingURL == nil)
        #expect(configuration.port == 8080)
        #expect(configuration.moonKeys == false)
    }

    @Test(arguments: [("true", true), ("false", false), (" true ", true)])
    func readsMoonKeys(value: String, expected: Bool) throws {
        var environment = required
        environment["ALERT_MOON_KEYS"] = value

        #expect(try Configuration(environment: environment).moonKeys == expected)
    }

    @Test(arguments: ["yes", "1", "TRUE", "on"])
    func invalidMoonKeysFail(value: String) {
        var environment = required
        environment["ALERT_MOON_KEYS"] = value

        #expect(throws: ConfigurationError.invalid("ALERT_MOON_KEYS")) { try Configuration(environment: environment) }
    }

    @Test func readsOptionalValues() throws {
        var environment = required
        environment["APNS_ENVIRONMENT"] = "sandbox"
        environment["HEALTHCHECK_PING_URL"] = "https://hc-ping.com/1234"
        environment["PORT"] = "9090"

        let configuration = try Configuration(environment: environment)

        #expect(configuration.apnsEnvironment == .sandbox)
        #expect(configuration.healthcheckPingURL?.absoluteString == "https://hc-ping.com/1234")
        #expect(configuration.port == 9090)
    }

    @Test(arguments: ["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_KEY_PATH", "APNS_TOPIC", "DATABASE_PATH"])
    func missingRequiredValueFails(name: String) {
        var environment = required
        environment[name] = nil

        #expect(throws: ConfigurationError.missing(name)) { try Configuration(environment: environment) }

        environment[name] = "  "
        #expect(throws: ConfigurationError.missing(name)) { try Configuration(environment: environment) }
    }

    @Test func invalidValuesFail() {
        var environment = required
        environment["APNS_ENVIRONMENT"] = "staging"
        #expect(throws: ConfigurationError.invalid("APNS_ENVIRONMENT")) { try Configuration(environment: environment) }

        environment = required
        environment["PORT"] = "http"
        #expect(throws: ConfigurationError.invalid("PORT")) { try Configuration(environment: environment) }

        environment = required
        environment["HEALTHCHECK_PING_URL"] = "not a url"
        #expect(throws: ConfigurationError.invalid("HEALTHCHECK_PING_URL")) { try Configuration(environment: environment) }
    }

    @Test func errorMessageNamesTheVariable() {
        #expect(ConfigurationError.missing("APNS_KEY_ID").description.contains("APNS_KEY_ID"))
    }
}
