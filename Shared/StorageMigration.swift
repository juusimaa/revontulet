import Foundation

/// Moves the app's earlier storage into the App Group, once and from the app only. Old files and
/// values stay in place. A failed copy only costs the instant result on the next launch.
enum StorageMigration {
    static let fileNames = ["last-result.json", "last-outlook.json"]

    static func run(
        legacyDirectory: URL = .applicationSupportDirectory,
        groupDirectory: URL = AppGroup.containerURL,
        standardDefaults: UserDefaults = .standard,
        groupDefaults: UserDefaults = AppGroup.defaults
    ) {
        let fileManager = FileManager.default
        if legacyDirectory.standardizedFileURL != groupDirectory.standardizedFileURL {
            for name in fileNames {
                let source = legacyDirectory.appending(path: name)
                let destination = groupDirectory.appending(path: name)
                guard fileManager.fileExists(atPath: source.path),
                      !fileManager.fileExists(atPath: destination.path) else { continue }
                try? fileManager.createDirectory(at: groupDirectory, withIntermediateDirectories: true)
                try? fileManager.copyItem(at: source, to: destination)
            }
        }
        if groupDefaults !== standardDefaults,
           groupDefaults.object(forKey: PlaceSelectionStore.key) == nil,
           let value = standardDefaults.string(forKey: PlaceSelectionStore.key) {
            groupDefaults.set(value, forKey: PlaceSelectionStore.key)
        }
    }
}
