import AlertServer
import AuroraCore
import Foundation

let logger = makeLogger()

let configuration: Configuration
do {
    configuration = try Configuration(environment: ProcessInfo.processInfo.environment)
} catch {
    logger.critical("\(error.description)")
    exit(1)
}

let store = try await RegistrationStore.open(path: configuration.databasePath)
let dependencies = try AppDependencies(
    store: store,
    health: HealthStatus(),
    rateLimiter: RateLimiter(),
    zones: AlertZones.all()
)

logger.info("alert-service \(AlertServer.version) starting (APNs \(configuration.apnsEnvironment.rawValue))")
let app = buildApplication(dependencies: dependencies, port: configuration.port, logger: logger)
try await app.runService()
try await store.close()
