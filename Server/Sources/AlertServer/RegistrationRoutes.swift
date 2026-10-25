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
}

/// Registration bodies are under 500 bytes; anything much larger is not a registration.
private let maxBodySize = 4_096
