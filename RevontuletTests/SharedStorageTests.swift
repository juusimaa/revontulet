import AuroraCore
import Foundation
import Testing
@testable import Revontulet

@Suite struct SharedStorageTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    @Test func copiesBothFilesOnce() throws {
        let legacy = try tempDirectory(), group = try tempDirectory()
        try Data("result".utf8).write(to: legacy.appending(path: "last-result.json"))
        try Data("outlook".utf8).write(to: legacy.appending(path: "last-outlook.json"))
        StorageMigration.run(legacyDirectory: legacy, groupDirectory: group,
                             standardDefaults: suite(), groupDefaults: suite())
        #expect(try Data(contentsOf: group.appending(path: "last-result.json")) == Data("result".utf8))
        #expect(try Data(contentsOf: group.appending(path: "last-outlook.json")) == Data("outlook".utf8))
        #expect(FileManager.default.fileExists(atPath: legacy.appending(path: "last-result.json").path))
    }

    @Test func neverOverwritesAGroupFile() throws {
        let legacy = try tempDirectory(), group = try tempDirectory()
        try Data("old".utf8).write(to: legacy.appending(path: "last-result.json"))
        try Data("new".utf8).write(to: group.appending(path: "last-result.json"))
        StorageMigration.run(legacyDirectory: legacy, groupDirectory: group,
                             standardDefaults: suite(), groupDefaults: suite())
        #expect(try Data(contentsOf: group.appending(path: "last-result.json")) == Data("new".utf8))
    }

    @Test func toleratesMissingSource() throws {
        let legacy = try tempDirectory(), group = try tempDirectory()
        StorageMigration.run(legacyDirectory: legacy, groupDirectory: group,
                             standardDefaults: suite(), groupDefaults: suite())
        #expect(!FileManager.default.fileExists(atPath: group.appending(path: "last-result.json").path))
    }

    @Test func copiesSelectionOnlyWhenSuiteHasNone() {
        let standard = suite(), group = suite()
        standard.set("091", forKey: "placeSelection")
        StorageMigration.run(legacyDirectory: URL(filePath: "/nonexistent"), groupDirectory: URL(filePath: "/nonexistent2"),
                             standardDefaults: standard, groupDefaults: group)
        #expect(group.string(forKey: "placeSelection") == "091")

        let other = suite()
        other.set("currentLocation", forKey: "placeSelection")
        StorageMigration.run(legacyDirectory: URL(filePath: "/nonexistent"), groupDirectory: URL(filePath: "/nonexistent2"),
                             standardDefaults: standard, groupDefaults: other)
        #expect(other.string(forKey: "placeSelection") == "currentLocation")
    }

    @MainActor
    @Test func secondStoreSeesFirstWrites() throws {
        let defaults = suite()
        PlaceSelectionStore(defaults: defaults).selection = .municipality(code: "091")
        #expect(PlaceSelectionStore(defaults: defaults).selection == .municipality(code: "091"))
    }

    @Test func secondCacheReadsTheSameFile() async throws {
        let url = try tempDirectory().appending(path: "last-outlook.json")
        #expect(await FileOutlookCache(fileURL: url).load() == nil)
        // Undecodable content reads as nothing cached.
        try Data("{}".utf8).write(to: url)
        #expect(await FileOutlookCache(fileURL: url).load() == nil)
        FileOutlookCache(fileURL: url).clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
