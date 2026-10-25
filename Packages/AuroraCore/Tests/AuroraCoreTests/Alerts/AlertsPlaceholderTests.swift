import Testing
@testable import AuroraCore

// Placeholder so Alerts/ is part of the test target; replaced by the alert tests in Phase 2.
@Test func alertsFolderBuilds() {
    #expect(!AuroraCore.version.isEmpty)
}
