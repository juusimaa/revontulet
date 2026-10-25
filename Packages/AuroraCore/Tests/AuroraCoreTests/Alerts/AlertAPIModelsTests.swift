import Foundation
import Testing
@testable import AuroraCore

@Suite("Alert API models")
struct AlertAPIModelsTests {
    private let zones = try! AlertZones.all()
    /// 32 bytes, the usual APNs token length.
    private let token = String(repeating: "a1", count: 32)

    private func upsert(token: String? = nil, zone: String = "OUJ", threshold: AlertThreshold = .high) -> RegistrationUpsert {
        RegistrationUpsert(token: token ?? self.token, zone: zone, threshold: threshold)
    }

    private func jsonObject(_ value: some Encodable) throws -> [String: String] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    // MARK: Coding

    @Test func upsertUsesContractFieldNames() throws {
        let object = try jsonObject(upsert(threshold: .moderate))

        #expect(object == ["token": token, "zone": "OUJ", "threshold": "moderate"])
    }

    @Test func upsertDecodesFromContractJSON() throws {
        let json = #"{ "token": "\#(token)", "zone": "KEV", "threshold": "high" }"#

        let decoded = try JSONDecoder().decode(RegistrationUpsert.self, from: Data(json.utf8))

        #expect(decoded == upsert(zone: "KEV", threshold: .high))
    }

    @Test func upsertRoundTrips() throws {
        let original = upsert(zone: "TAR", threshold: .moderate)

        let decoded = try JSONDecoder().decode(RegistrationUpsert.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
    }

    @Test func tokenUsesContractFieldName() throws {
        let original = RegistrationToken(token: token)

        #expect(try jsonObject(original) == ["token": token])
        let decoded = try JSONDecoder().decode(RegistrationToken.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func unknownThresholdDoesNotDecode() {
        let json = #"{ "token": "\#(token)", "zone": "KEV", "threshold": "low" }"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RegistrationUpsert.self, from: Data(json.utf8))
        }
    }

    @Test func thresholdRawValuesAndDefault() {
        #expect(AlertThreshold.allCases.map(\.rawValue) == ["moderate", "high"])
        #expect(AlertThreshold.default == .high)
    }

    @Test func errorRawValuesMatchContract() throws {
        #expect(AlertAPIError.allCases.map(\.rawValue) == ["invalidToken", "invalidZone", "invalidThreshold", "invalidBody"])
        let body = try JSONEncoder().encode(["error": AlertAPIError.invalidZone])
        #expect(String(decoding: body, as: UTF8.self) == #"{"error":"invalidZone"}"#)
    }

    // MARK: Validation

    @Test func validRegistrationPasses() {
        #expect(RegistrationValidation.validate(upsert(), zones: zones) == nil)
        #expect(RegistrationValidation.validate(upsert(token: String(repeating: "0f", count: 200)), zones: zones) == nil)
        #expect(RegistrationValidation.validate(upsert(token: String(repeating: "9e", count: 100)), zones: zones) == nil)
    }

    @Test(arguments: [
        String(repeating: "ab", count: 31),   // 31 bytes: too short
        String(repeating: "ab", count: 201),  // 201 bytes: too long
        String(repeating: "ab", count: 32) + "a",  // odd length
        String(repeating: "AB", count: 32),   // uppercase
        String(repeating: "zz", count: 32),   // not hex
        String(repeating: "ab", count: 31) + "a ",  // whitespace
        "",
    ])
    func invalidTokenRejected(token: String) {
        #expect(RegistrationValidation.validate(upsert(token: token), zones: zones) == .invalidToken)
        #expect(RegistrationValidation.validate(RegistrationToken(token: token)) == .invalidToken)
    }

    @Test func validTokenOnlyRequestPasses() {
        #expect(RegistrationValidation.validate(RegistrationToken(token: token)) == nil)
    }

    @Test(arguments: ["", "ouj", "XXX", "Oulujärvi", "OUJ "])
    func unknownZoneRejected(zone: String) {
        #expect(RegistrationValidation.validate(upsert(zone: zone), zones: zones) == .invalidZone)
    }

    @Test func everyStationCodeIsAValidZone() {
        for zone in zones {
            #expect(RegistrationValidation.validate(upsert(zone: zone.id), zones: zones) == nil)
        }
    }

    @Test func invalidThresholdInRawBodyRejected() {
        let json = #"{ "token": "\#(token)", "zone": "KEV", "threshold": "low" }"#

        #expect(RegistrationValidation.decodeUpsert(Data(json.utf8), zones: zones) == .failure(.invalidThreshold))
    }

    @Test func rawBodyDecoding() {
        let valid = #"{ "token": "\#(token)", "zone": "OUJ", "threshold": "high" }"#
        #expect(RegistrationValidation.decodeUpsert(Data(valid.utf8), zones: zones) == .success(upsert()))

        #expect(RegistrationValidation.decodeUpsert(Data("not json".utf8), zones: zones) == .failure(.invalidBody))
        #expect(RegistrationValidation.decodeUpsert(Data(#"{"token":"\#(token)"}"#.utf8), zones: zones) == .failure(.invalidBody))
        let badZone = #"{ "token": "\#(token)", "zone": "XXX", "threshold": "high" }"#
        #expect(RegistrationValidation.decodeUpsert(Data(badZone.utf8), zones: zones) == .failure(.invalidZone))
        let badToken = #"{ "token": "AB", "zone": "OUJ", "threshold": "high" }"#
        #expect(RegistrationValidation.decodeUpsert(Data(badToken.utf8), zones: zones) == .failure(.invalidToken))
    }

    @Test func rawTokenBodyDecoding() {
        #expect(RegistrationValidation.decodeToken(Data(#"{"token":"\#(token)"}"#.utf8)) == .success(RegistrationToken(token: token)))
        #expect(RegistrationValidation.decodeToken(Data("[]".utf8)) == .failure(.invalidBody))
        #expect(RegistrationValidation.decodeToken(Data(#"{"token":"xyz"}"#.utf8)) == .failure(.invalidToken))
    }
}
