import Foundation
import Combine
import SoyleKit

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
    /// Last persistence problem, shown in the History tab — these are the
    /// user's words, losing them must never be invisible.
    @Published private(set) var lastError: String?

    private let maxItems = 500
    private let fileURL: URL
    private let errorLog: ErrorLog

    /// Directory AND journal are injectable so tests touch neither the real
    /// history nor the real error journal.
    init(directory: URL? = nil, errorLog: ErrorLog = .shared) {
        self.errorLog = errorLog
        let dir = directory ?? FileManager.default
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            // Never overwrite what we can't read — park the damaged file so
            // the transcripts stay recoverable, and say what happened.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            lastError = "History couldn't be read — the damaged file was kept as \(backup.lastPathComponent)."
            errorLog.record(component: "history",
                            message: "history.json unreadable — moved aside, starting fresh",
                            detail: error.localizedDescription)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
            if lastError != nil { lastError = nil }
        } catch {
            lastError = "History couldn't be saved — \(error.localizedDescription)"
            errorLog.record(component: "history",
                            message: "history.json save failed",
                            detail: error.localizedDescription)
        }
    }
}
