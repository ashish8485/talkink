import Foundation
import Combine

struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    let language: String?

    init(text: String, language: String?) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.language = language
    }
}

/// Persistent history of transcriptions, so anything that didn't paste (or got
/// lost) can be retrieved and re-copied from the app — like Wispr Flow.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []

    private let maxItems = 500
    private let fileURL: URL

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Soyle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, language: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(HistoryItem(text: trimmed, language: language), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save()
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
