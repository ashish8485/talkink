import Foundation
import Combine

/// One recorded failure. `message` is written for the user (it may be shown in
/// Settings and in problem reports); `detail` carries the technical error.
/// Transcript text and audio NEVER belong in here — the journal feeds
/// "Report a Problem" and must stay free of user content.
public struct LoggedError: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let component: String
    public let message: String
    public let detail: String?

    public init(component: String, message: String, detail: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.component = component
        self.message = message
        self.detail = detail
    }
}

/// Persistent journal of the most recent errors, so "something failed" is
/// never lost with the process: the user can see the last issues in Settings
/// and attach them to a GitHub report. Safe to call from any thread.
public final class ErrorLog: ObservableObject, @unchecked Sendable {
    public static let shared = ErrorLog()

    /// Main-thread mirror for SwiftUI. Newest first.
    @Published public private(set) var entries: [LoggedError] = []

    private var storage: [LoggedError] = []   // source of truth, lock-protected
    private let lock = NSLock()
    private let persistQueue = DispatchQueue(label: "soyle.errorlog", qos: .utility)
    private let fileURL: URL
    private let maxEntries = 100

    public convenience init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Soyle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(fileURL: dir.appendingPathComponent("errors.json"))
    }

    /// Injectable storage location, so tests never touch the real journal.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([LoggedError].self, from: data) {
            storage = decoded
        }
        let snapshot = storage
        if Thread.isMainThread { entries = snapshot }
        else { DispatchQueue.main.async { self.entries = snapshot } }
    }

    /// Record a failure: system log + journal + UI mirror.
    public func record(component: String, message: String, detail: String? = nil) {
        Log.app.error("[\(component, privacy: .public)] \(message, privacy: .public) — \(detail ?? "", privacy: .public)")
        let entry = LoggedError(component: component, message: message, detail: detail)
        lock.lock()
        storage.insert(entry, at: 0)
        if storage.count > maxEntries { storage.removeLast(storage.count - maxEntries) }
        let snapshot = storage
        lock.unlock()
        persistQueue.async { [fileURL] in
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        DispatchQueue.main.async { self.entries = snapshot }
    }

    /// Thread-safe snapshot (newest first) for diagnostics reports.
    public func recent(_ count: Int = 10) -> [LoggedError] {
        lock.lock(); defer { lock.unlock() }
        return Array(storage.prefix(count))
    }

    public func clear() {
        lock.lock(); storage.removeAll(); lock.unlock()
        persistQueue.async { [fileURL] in try? FileManager.default.removeItem(at: fileURL) }
        DispatchQueue.main.async { self.entries = [] }
    }

    /// Blocks until pending disk writes land — for tests only.
    public func waitForWrites() {
        persistQueue.sync {}
    }
}
