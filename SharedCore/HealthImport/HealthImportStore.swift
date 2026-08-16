import Foundation

/// Persists the last imported health export as compact JSON in Application
/// Support, so launches after an import are instant (no re-parse).
final class HealthImportStore {
    private let fileURL: URL?
    private(set) var hasImport: Bool

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = support?.appendingPathComponent("myhealth", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        fileURL = directory?.appendingPathComponent("health-import.json")
        hasImport = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func load() -> ParsedHealthExport? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ParsedHealthExport.self, from: data)
    }

    func save(_ export: ParsedHealthExport) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(export) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic])
            hasImport = true
        } catch {
            // Import still works this session; it just won't persist.
        }
    }

    func delete() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        hasImport = false
    }
}
