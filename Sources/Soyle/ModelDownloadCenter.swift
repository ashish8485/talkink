import Foundation
import SoyleKit

/// Single source of truth for every catalog model's on-disk/download state.
/// Downloads run concurrently (one task per repo), are cancellable, and
/// resume byte-exactly thanks to `ModelDownloader`'s `.part` files — so the
/// user can queue several models at once, quit, relaunch, and lose nothing.
/// Selection (which model dictation uses) is deliberately independent.
@MainActor
final class ModelDownloadCenter: ObservableObject {
    static let shared = ModelDownloadCenter()

    enum ModelState: Equatable {
        case notDownloaded
        case paused(Double)        // interrupted download — this much already on disk
        case downloading(Double)   // 0…1, byte-accurate
        case downloaded            // complete on disk, not the active model
        case preparing             // selected: weights → memory / Metal warm-up
        case active                // selected, loaded, ready to dictate
        case failed                // download failed (offline…) — retryable
    }

    @Published private(set) var states: [String: ModelState] = [:]

    private var downloadTasks: [String: Task<Void, Error>] = [:]

    private init() {
        refreshFromDisk()
    }

    func state(of option: ASRModelOption) -> ModelState {
        states[option.id] ?? .notDownloaded
    }

    var anyDownloading: Bool {
        states.values.contains { if case .downloading = $0 { return true } else { return false } }
    }

    /// Re-derive on-disk states from the cache without clobbering rows that
    /// are mid-download or loading. An interrupted download (quit, cancel,
    /// crash) shows up as `.paused` with its real on-disk fraction, so the
    /// user knows the bytes are safe and one click resumes.
    func refreshFromDisk() {
        for option in ASRCatalog.options {
            switch states[option.id] {
            case .downloading, .preparing, .active:
                continue
            default:
                if ModelDownloader.isCached(repo: option.id) {
                    states[option.id] = .downloaded
                } else if let fraction = ModelDownloader.partialFraction(
                    repo: option.id, expectedBytes: Int64(option.sizeGB * 1_000_000_000)) {
                    states[option.id] = .paused(fraction)
                } else {
                    states[option.id] = .notDownloaded
                }
            }
        }
    }

    /// Start (or join) the concurrent download of one model. Safe to call for
    /// a model that's already downloading or on disk.
    @discardableResult
    func ensureDownloaded(_ option: ASRModelOption) -> Task<Void, Error> {
        if let running = downloadTasks[option.id] { return running }
        switch state(of: option) {
        case .downloaded, .preparing, .active:
            return Task {}
        default:
            break
        }
        states[option.id] = .downloading(0)
        let task = Task<Void, Error> { [weak self] in
            do {
                try await ModelDownloader.download(repo: option.id) { fraction in
                    Task { @MainActor [weak self] in
                        // Only while still downloading — a cancel may have landed.
                        if case .downloading = self?.states[option.id] ?? .notDownloaded {
                            self?.states[option.id] = .downloading(fraction)
                        }
                    }
                }
                await MainActor.run { [weak self] in
                    self?.downloadTasks[option.id] = nil
                    self?.states[option.id] = .downloaded
                }
            } catch {
                let cancelled = error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.downloadTasks[option.id] = nil
                    if ModelDownloader.isCached(repo: option.id) {
                        self.states[option.id] = .downloaded
                    } else if cancelled {
                        // Partial bytes stay on disk — surface them so the row
                        // says "Resume" with the real fraction.
                        if let fraction = ModelDownloader.partialFraction(
                            repo: option.id, expectedBytes: Int64(option.sizeGB * 1_000_000_000)) {
                            self.states[option.id] = .paused(fraction)
                        } else {
                            self.states[option.id] = .notDownloaded
                        }
                    } else {
                        self.states[option.id] = .failed
                    }
                }
                throw error
            }
        }
        downloadTasks[option.id] = task
        return task
    }

    /// Cancel an in-flight download. The `.part` partial stays on disk, so a
    /// later download resumes instead of restarting.
    func cancelDownload(_ option: ASRModelOption) {
        downloadTasks[option.id]?.cancel()
    }

    // MARK: Selected-model load lifecycle (driven by AppDelegate)

    func markPreparing(_ option: ASRModelOption) {
        states[option.id] = .preparing
    }

    func markActive(_ option: ASRModelOption) {
        for (id, state) in states where state == .active {
            states[id] = .downloaded
        }
        states[option.id] = .active
    }

    /// The selected model failed to load (not download) — put its row back to
    /// whatever the disk says.
    func clearLoadMarker(_ option: ASRModelOption) {
        states[option.id] = ModelDownloader.isCached(repo: option.id)
            ? .downloaded : .notDownloaded
    }

    /// Delete a downloaded model from disk. Refused for the model in use —
    /// the UI requires switching first, so dictation can never lose its
    /// weights mid-flight.
    func deleteFromDisk(_ option: ASRModelOption) {
        switch state(of: option) {
        case .active, .preparing, .downloading:
            return
        default:
            break
        }
        do {
            try ModelDownloader.delete(repo: option.id)
            states[option.id] = .notDownloaded
        } catch {
            NSLog("Talkink: model delete failed: \(error.localizedDescription)")
            refreshFromDisk()
        }
    }
}
