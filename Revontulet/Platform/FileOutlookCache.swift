import AuroraCore
import Foundation

/// Keeps the last outlook snapshot as a JSON file in Application Support, separate from the
/// headline's cache, so an unreadable snapshot never affects the headline. Written atomically,
/// stays on the device and is excluded from backups.
struct FileOutlookCache: OutlookCache {
    let fileURL: URL

    init(fileURL: URL = FileOutlookCache.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "last-outlook.json")
    }

    func load() async -> OutlookSnapshot? {
        // A missing or undecodable file (e.g. after a format change) just means no snapshot.
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(OutlookSnapshot.self, from: data)
    }

    func save(_ snapshot: OutlookSnapshot) async {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            // Not being able to cache only costs the instant outlook on the next launch.
        }
    }

    /// Removes the snapshot, for UI tests that need a clean first launch.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
