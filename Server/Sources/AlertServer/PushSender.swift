import APNS
import APNSCore
import AsyncHTTPClient
import AuroraCore
import Crypto
import Foundation
import Logging

/// One notification to one device.
public struct PushRequest: Sendable, Equatable {
    public var token: String
    public var message: AlertMessage
    /// `apns-expiration`: APNs drops the alert if it cannot be delivered by then (FR-009).
    public var expiration: Date?
    /// `apns-collapse-id`: a retried send never shows twice.
    public var collapseID: String?

    public init(token: String, message: AlertMessage, expiration: Date?, collapseID: String?) {
        self.token = token
        self.message = message
        self.expiration = expiration
        self.collapseID = collapseID
    }
}

/// What an APNs response means for the dispatcher (contracts/push-notification.md).
public enum PushResult: Sendable, Equatable {
    case delivered
    /// 410 Unregistered / ExpiredToken, with the response's timestamp.
    case unregistered(timestamp: Date?)
    /// 400 BadDeviceToken / DeviceTokenNotForTopic.
    case badDeviceToken
    /// 403 ExpiredProviderToken / InvalidProviderToken and other authentication errors.
    case providerTokenRejected
    /// 429, 5xx or no response.
    case retryable
    /// Any other rejection; dropped.
    case rejected
}

public protocol PushSender: Sendable {
    func send(_ request: PushRequest) async -> PushResult
}

/// The APNs payload, exactly as contracts/push-notification.md: localisation keys and the station
/// name, default sound, one thread; no badge, no interruption level, no custom data.
struct AlertPayload: APNSMessage, Equatable {
    struct APS: Encodable, Equatable {
        struct Alert: Encodable, Equatable {
            var titleKey: String
            var bodyKey: String
            var arguments: [String]

            enum CodingKeys: String, CodingKey {
                case titleKey = "title-loc-key"
                case bodyKey = "loc-key"
                case arguments = "loc-args"
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(titleKey, forKey: .titleKey)
                try container.encode(bodyKey, forKey: .bodyKey)
                if !arguments.isEmpty { try container.encode(arguments, forKey: .arguments) }
            }
        }

        var alert: Alert
        var sound = "default"
        var threadID = "aurora-alerts"

        enum CodingKeys: String, CodingKey {
            case alert, sound
            case threadID = "thread-id"
        }
    }

    var aps: APS

    init(_ message: AlertMessage) {
        aps = APS(alert: APS.Alert(titleKey: message.titleKey, bodyKey: message.bodyKey, arguments: message.arguments))
    }
}

/// Sends to APNs with token (JWT) authentication, to the instance's one environment.
public final class APNSPushSender: PushSender {
    private let client: APNSClient<JSONDecoder, JSONEncoder>
    private let topic: String
    private let logger: Logger

    public init(configuration: Configuration, logger: Logger) throws {
        let pem = try String(contentsOfFile: configuration.apnsKeyPath, encoding: .utf8)
        client = APNSClient(
            configuration: APNSClientConfiguration(
                authenticationMethod: .jwt(
                    privateKey: try P256.Signing.PrivateKey(pemRepresentation: pem),
                    keyIdentifier: configuration.apnsKeyID,
                    teamIdentifier: configuration.apnsTeamID),
                environment: configuration.apnsEnvironment == .production ? .production : .development),
            eventLoopGroupProvider: .shared(HTTPClient.defaultEventLoopGroup),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder())
        topic = configuration.apnsTopic
        self.logger = logger
    }

    public func shutdown() async throws {
        try await client.shutdown()
    }

    public func send(_ request: PushRequest) async -> PushResult {
        do {
            _ = try await client.send(Self.apnsRequest(for: request, topic: topic))
            return .delivered
        } catch let error as APNSError {
            let result = Self.result(for: error)
            // Never log the token; the reason is enough to diagnose configuration errors.
            if result != .unregistered(timestamp: error.timestamp) {
                logger.warning("APNs rejected a notification", metadata: [
                    "status": "\(error.responseStatus)", "reason": "\(error.reason?.reason ?? "none")",
                ])
            }
            return result
        } catch {
            logger.warning("APNs request failed", metadata: ["error": "\(type(of: error))"])
            return .retryable
        }
    }

    static func apnsRequest(for request: PushRequest, topic: String) -> APNSRequest<AlertPayload> {
        APNSRequest(
            message: AlertPayload(request.message),
            deviceToken: request.token,
            pushType: .alert,
            expiration: request.expiration.map { .timeIntervalSince1970InSeconds(Int($0.timeIntervalSince1970)) },
            priority: .immediately,
            apnsID: nil,
            topic: topic,
            collapseID: request.collapseID)
    }

    static func result(for error: APNSError) -> PushResult {
        switch error.responseStatus {
        case 410:
            return .unregistered(timestamp: error.timestamp)
        case 400 where error.reason == .badDeviceToken || error.reason == .deviceTokenNotForTopic:
            return .badDeviceToken
        case 403:
            return .providerTokenRejected
        case 429, 500...599:
            return .retryable
        default:
            return .rejected
        }
    }
}
