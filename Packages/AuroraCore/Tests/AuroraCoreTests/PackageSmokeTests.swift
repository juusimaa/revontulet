import Testing
@testable import AuroraCore

@Test func packageBuilds() {
    #expect(!AuroraCore.version.isEmpty)
}
