import Testing
@testable import AlertServer

@Test func packageBuilds() {
    #expect(!AlertServer.version.isEmpty)
}
