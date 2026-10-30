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
let pushSender = try APNSPushSender(configuration: configuration, logger: logger)
let httpClient = AsyncHTTPClientFMI.makeClient()
let health = HealthStatus()

let evaluationLoop = EvaluationLoop(
    source: try ZoneEvaluator(http: AsyncHTTPClientFMI(client: httpClient)),
    store: store,
    dispatcher: Dispatcher(
        store: store, sender: pushSender, topic: configuration.apnsTopic, moonKeys: configuration.moonKeys),
    health: health,
    heartbeat: HealthcheckPinger(url: configuration.healthcheckPingURL, client: httpClient, logger: logger),
    logger: logger
)
let maintenance = Maintenance(store: store, backupPath: configuration.backupPath, logger: logger)
let dependencies = try AppDependencies(
    store: store,
    health: health,
    rateLimiter: RateLimiter(),
    zones: AlertZones.all(),
    pushSender: pushSender,
    apnsTopic: configuration.apnsTopic
)

logger.info("alert-service \(AlertServer.version) starting (APNs \(configuration.apnsEnvironment.rawValue))")
let app = buildApplication(dependencies: dependencies, port: configuration.port, services: [evaluationLoop, maintenance], logger: logger)
try await app.runService()

try? await pushSender.shutdown()
try? await httpClient.shutdown().get()
try await store.close()
