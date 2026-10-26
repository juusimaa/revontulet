import AuroraCore
import Foundation
import Hummingbird

/// `/v1/registration` (contracts/alert-api.md). Bodies are never logged.
func addRegistrationRoutes(to group: RouterGroup<BasicRequestContext>, dependencies: AppDependencies) {
    group.put { request, _ -> Response in
        guard let body = try? await request.body.collect(upTo: maxBodySize) else { return .apiError(.invalidBody) }
        switch RegistrationValidation.decodeUpsert(Data(body.readableBytesView), zones: dependencies.zones) {
        case .success(let upsert):
            try await dependencies.store.upsert(upsert, now: dependencies.now())
            return Response(status: .noContent)
        case .failure(let error):
            return .apiError(error)
        }
    }

    // 204 whether or not the registration existed, so retries are safe.
    group.post("delete") { request, _ -> Response in
        guard let body = try? await request.body.collect(upTo: maxBodySize) else { return .apiError(.invalidBody) }
        switch RegistrationValidation.decodeToken(Data(body.readableBytesView)) {
        case .success(let token):
            try await dependencies.store.delete(token: token.token)
            return Response(status: .noContent)
        case .failure(let error):
            return .apiError(error)
        }
    }

    // 404 before counting, so a re-registering app is not limited by its failed attempt.
    group.post("test") { request, _ -> Response in
        guard let body = try? await request.body.collect(upTo: maxBodySize) else { return .apiError(.invalidBody) }
        switch RegistrationValidation.decodeToken(Data(body.readableBytesView)) {
        case .success(let token):
            guard try await dependencies.store.registration(token: token.token) != nil else {
                return Response(status: .notFound)
            }
            let now = dependencies.now()
            if case .limited(let retryAfter) = await dependencies.testRateLimiter.check(token.token, now: now) {
                return Response(status: .tooManyRequests, headers: [.retryAfter: String(retryAfter)])
            }
            let push = PushRequest(token: token.token, message: .test, expiration: now.addingTimeInterval(testExpiry),
                                   collapseID: nil)
            guard await dependencies.pushSender.send(push) == .delivered else { return Response(status: .serviceUnavailable) }
            return Response(status: .accepted)
        case .failure(let error):
            return .apiError(error)
        }
    }
}

/// A test notification older than this is no use to the user waiting for it.
private let testExpiry: TimeInterval = 15 * 60

/// Registration bodies are under 500 bytes; anything much larger is not a registration.
private let maxBodySize = 4_096
