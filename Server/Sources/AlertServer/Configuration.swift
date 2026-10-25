import Foundation

/// Service configuration from environment variables (Server/deploy/alerts.env.example).
public struct Configuration: Sendable, Equatable {
    public enum APNSEnvironment: String, Sendable {
        /// api.push.apple.com, for TestFlight and App Store builds.
        case production
        /// api.sandbox.push.apple.com, for a development instance and Debug builds.
        case sandbox
    }

    public var apnsKeyID: String
    public var apnsTeamID: String
    /// PEM private key (the `.p8` converted with `openssl pkcs8`).
    public var apnsKeyPath: String
    public var apnsTopic: String
    public var apnsEnvironment: APNSEnvironment
    /// Heartbeat pinged after every cycle; nil disables the heartbeat (local development).
    public var healthcheckPingURL: URL?
    public var databasePath: String
    public var port: Int

    /// Fails with the name of the first missing or invalid variable.
    public init(environment: [String: String]) throws(ConfigurationError) {
        func value(_ name: String) -> String? {
            environment[name].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        func required(_ name: String) throws(ConfigurationError) -> String {
            guard let value = value(name) else { throw .missing(name) }
            return value
        }

        apnsKeyID = try required("APNS_KEY_ID")
        apnsTeamID = try required("APNS_TEAM_ID")
        apnsKeyPath = try required("APNS_KEY_PATH")
        apnsTopic = try required("APNS_TOPIC")
        databasePath = try required("DATABASE_PATH")

        guard let environmentName = APNSEnvironment(rawValue: value("APNS_ENVIRONMENT") ?? "production") else {
            throw .invalid("APNS_ENVIRONMENT")
        }
        apnsEnvironment = environmentName

        if let ping = value("HEALTHCHECK_PING_URL") {
            guard let url = URL(string: ping), url.scheme == "https" || url.scheme == "http", url.host != nil else {
                throw .invalid("HEALTHCHECK_PING_URL")
            }
            healthcheckPingURL = url
        }

        guard let port = Int(value("PORT") ?? "8080"), (0...65_535).contains(port) else { throw .invalid("PORT") }
        self.port = port
    }
}

public enum ConfigurationError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .missing(let name): "Missing required environment variable \(name) (see Server/deploy/alerts.env.example)"
        case .invalid(let name): "Invalid value for environment variable \(name) (see Server/deploy/alerts.env.example)"
        }
    }
}
