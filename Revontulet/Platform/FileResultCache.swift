import AuroraCore
import Foundation

/// Keeps the last result as a JSON file in Application Support. The file is written atomically,
/// stays on the device and is excluded from backups (it is cheap to recreate).
struct FileResultCache: ResultCache {
    let fileURL: URL

    init(fileURL: URL = FileResultCache.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "last-result.json")
    }

    func load() async -> AuroraResult? {
        // A missing or unreadable file (e.g. after a format change) just means no cached result.
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AuroraResult.self, from: data)
    }

    func save(_ result: AuroraResult) async {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(result).write(to: fileURL, options: [.atomic])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            // Not being able to cache only costs the instant result on the next launch.
        }
    }

    /// Removes the cached result, for UI tests that need a clean first launch.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
