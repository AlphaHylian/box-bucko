import Foundation

struct SkinEntry: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var fileName: String
    var addedAt: Date
}

/// Manages the on-disk collection of skins the user has imported, persisted
/// under Application Support so they survive app restarts.
final class SkinLibrary {
    static let shared = SkinLibrary()

    private(set) var entries: [SkinEntry] = []

    private let fileManager = FileManager.default
    private let directory: URL
    private let indexURL: URL

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("BoxBucko/Skins", isDirectory: true)
        indexURL = base.appendingPathComponent("BoxBucko/skins.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        loadIndex()
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SkinEntry].self, from: data) else { return }
        entries = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    func url(for entry: SkinEntry) -> URL {
        directory.appendingPathComponent(entry.fileName)
    }

    @discardableResult
    func importSkin(from sourceURL: URL, name: String? = nil) throws -> SkinEntry {
        let id = UUID().uuidString
        let fileName = id + ".png"
        let destination = directory.appendingPathComponent(fileName)
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: destination, options: .atomic)
        let entry = SkinEntry(
            id: id,
            name: name ?? sourceURL.deletingPathExtension().lastPathComponent,
            fileName: fileName,
            addedAt: Date()
        )
        entries.append(entry)
        saveIndex()
        return entry
    }

    func remove(_ entry: SkinEntry) {
        try? fileManager.removeItem(at: url(for: entry))
        entries.removeAll { $0.id == entry.id }
        saveIndex()
    }

    func rename(_ entry: SkinEntry, to newName: String) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].name = newName
        saveIndex()
    }

    func entry(withID id: String) -> SkinEntry? {
        entries.first { $0.id == id }
    }
}
