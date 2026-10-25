import Foundation

/// The lowest chance level a registration is alerted for (FR-003). Raw values are part of the
/// HTTP contract.
public enum AlertThreshold: String, Sendable, Codable, CaseIterable {
    /// Alert on Moderate and High.
    case moderate
    /// Alert on High only.
    case high

    public static let `default`: AlertThreshold = .high
}

/// Body of `PUT /v1/registration` (contracts/alert-api.md).
public struct RegistrationUpsert: Sendable, Codable, Equatable {
    /// APNs device token, lowercase hex.
    public var token: String
    /// Zone (station code).
    public var zone: String
    public var threshold: AlertThreshold

    public init(token: String, zone: String, threshold: AlertThreshold) {
        self.token = token
        self.zone = zone
        self.threshold = threshold
    }
}

/// Body of `POST /v1/registration/delete` and `POST /v1/registration/test`.
public struct RegistrationToken: Sendable, Codable, Equatable {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}

/// The `error` value of a `400` response.
public enum AlertAPIError: String, Sendable, Codable, CaseIterable, Error {
    case invalidToken, invalidZone, invalidThreshold, invalidBody
}

/// Validation of registration requests, shared so the app never sends what the service rejects.
public enum RegistrationValidation {
    /// Decoded token length in bytes.
    static let tokenBytes = 32...200

    public static func validate(_ upsert: RegistrationUpsert, zones: [AlertZone]) -> AlertAPIError? {
        if !isValidToken(upsert.token) { return .invalidToken }
        if !zones.contains(where: { $0.id == upsert.zone }) { return .invalidZone }
        return nil
    }

    public static func validate(_ token: RegistrationToken) -> AlertAPIError? {
        isValidToken(token.token) ? nil : .invalidToken
    }

    /// Decodes and validates a raw `PUT /v1/registration` body, telling an unknown threshold
    /// (`invalidThreshold`) apart from a malformed body (`invalidBody`).
    public static func decodeUpsert(_ body: Data, zones: [AlertZone]) -> Result<RegistrationUpsert, AlertAPIError> {
        guard let raw = try? JSONDecoder().decode(RawUpsert.self, from: body) else { return .failure(.invalidBody) }
        if !isValidToken(raw.token) { return .failure(.invalidToken) }
        if !zones.contains(where: { $0.id == raw.zone }) { return .failure(.invalidZone) }
        guard let threshold = AlertThreshold(rawValue: raw.threshold) else { return .failure(.invalidThreshold) }
        return .success(RegistrationUpsert(token: raw.token, zone: raw.zone, threshold: threshold))
    }

    /// Decodes and validates a raw token-only body.
    public static func decodeToken(_ body: Data) -> Result<RegistrationToken, AlertAPIError> {
        guard let token = try? JSONDecoder().decode(RegistrationToken.self, from: body) else { return .failure(.invalidBody) }
        if let error = validate(token) { return .failure(error) }
        return .success(token)
    }

    /// Lowercase hex, even length, 32–200 bytes when decoded.
    static func isValidToken(_ token: String) -> Bool {
        let utf8 = token.utf8
        return utf8.count.isMultiple(of: 2)
            && tokenBytes.contains(utf8.count / 2)
            && utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0) }
    }

    private struct RawUpsert: Decodable {
        var token: String
        var zone: String
        var threshold: String
    }
}
