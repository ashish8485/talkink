import Foundation
import HuggingFace

/// Resumable Hugging Face model downloader — the behaviour users know from
/// `huggingface_hub`: a `.part` file next to the target plus HTTP `Range`
/// requests, so an interrupted download (quit, crash, network drop) resumes
/// where it stopped instead of restarting from zero. The library's own
/// `downloadSnapshot` streams into a hidden URLSession temp file and restarts
/// whole files on interruption, which is what this replaces.
///
/// Files land directly in the mlx-audio cache layout that
/// `ModelUtils.resolveOrDownloadModel` validates (flat directory, non-empty
/// safetensors + parseable config.json), so `fromPretrained` finds a complete
/// model afterwards and never re-downloads.
public enum ModelDownloader {

    public enum DownloadError: LocalizedError {
        case badStatus(Int, String)

        public var errorDescription: String? {
            switch self {
            case .badStatus(let code, let path):
                return "Download of \(path) failed (HTTP \(code))."
            }
        }
    }

    /// One file entry from `GET /api/models/{repo}/tree/main`.
    private struct TreeEntry: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    /// Mirrors the allow-list in `ModelUtils.resolveOrDownloadModel`.
    private static let wantedExtensions: Set<String> = ["safetensors", "json", "txt", "wav"]

    private static var hfToken: String? {
        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
        return (token?.isEmpty == false) ? token : nil
    }

    /// Same directory `ModelUtils` resolves for this repo.
    public static func modelDirectory(forRepo repoID: String) -> URL {
        HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(repoID.replacingOccurrences(of: "/", with: "_"))
    }

    /// True when the cache already passes the same completeness check the
    /// loader applies (non-empty safetensors + valid config.json) — in that
    /// case `fromPretrained` will use it as-is.
    public static func isCached(repo repoID: String) -> Bool {
        isCachedDirectory(modelDirectory(forRepo: repoID))
    }

    /// Testable core of `isCached` (the real cache path is fixed by HubCache).
    static func isCachedDirectory(_ dir: URL) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return false }
        let hasWeights = files.contains { file in
            file.pathExtension == "safetensors"
                && ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
        }
        guard hasWeights else { return false }
        let config = dir.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: config),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return false }
        return true
    }

    /// Download every model file, resumably. `onProgress` receives a global
    /// byte-accurate fraction (0…1), throttled to whole-percent steps —
    /// unthrottled 10 Hz UI updates caused visible main-thread layout churn.
    /// Files already complete on disk are skipped (file-level resume);
    /// half-downloaded files continue from their last byte (byte-level resume).
    public static func download(
        repo repoID: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let dir = modelDirectory(forRepo: repoID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let files = try await listFiles(repo: repoID)
        let totalBytes = max(files.reduce(Int64(0)) { $0 + ($1.size ?? 0) }, 1)
        let gate = PercentGate()
        let report: @Sendable (Int64) -> Void = { doneBytes in
            let fraction = min(Double(doneBytes) / Double(totalBytes), 1.0)
            if gate.admit(fraction) { onProgress(fraction) }
        }

        var settledBytes: Int64 = 0
        for file in files {
            // The loader only scans the directory root, and mlx-community
            // repos are flat — collapse any odd nesting to the filename.
            let dest = dir.appendingPathComponent((file.path as NSString).lastPathComponent)
            if let want = file.size, fileSize(at: dest) == want {
                settledBytes += want
                report(settledBytes)
                continue
            }
            let base = settledBytes
            try await fetch(repo: repoID, file: file, to: dest) { fileBytes in
                report(base + fileBytes)
            }
            settledBytes += file.size ?? fileSize(at: dest)
            report(settledBytes)
        }
        onProgress(1.0)
    }

    // MARK: - Internals

    /// Throttles progress callbacks to whole-percent changes.
    private final class PercentGate: @unchecked Sendable {
        private var lastPercent = -1
        private let lock = NSLock()
        func admit(_ fraction: Double) -> Bool {
            let percent = Int(fraction * 100)
            lock.lock(); defer { lock.unlock() }
            guard percent != lastPercent else { return false }
            lastPercent = percent
            return true
        }
    }

    private static func listFiles(repo repoID: String) async throws -> [TreeEntry] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoID)/tree/main") else {
            throw DownloadError.badStatus(-1, repoID)
        }
        var request = URLRequest(url: url)
        if let token = hfToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw DownloadError.badStatus(status, repoID) }
        return try JSONDecoder().decode([TreeEntry].self, from: data)
            .filter { entry in
                entry.type == "file"
                    && wantedExtensions.contains(URL(fileURLWithPath: entry.path).pathExtension.lowercased())
            }
    }

    /// Download one file into `dest`, streaming through `dest.part` with
    /// byte-range resume. `onFileProgress` receives bytes-on-disk for this file.
    private static func fetch(
        repo repoID: String,
        file: TreeEntry,
        to dest: URL,
        onFileProgress: @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        let part = dest.appendingPathExtension("part")
        var offset = fileSize(at: part)

        let escapedPath = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
        guard let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(escapedPath)") else {
            throw DownloadError.badStatus(-1, file.path)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if let token = hfToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.badStatus(-1, file.path) }
        switch http.statusCode {
        case 206:
            break                          // resuming where we stopped
        case 200:
            try? fm.removeItem(at: part)   // server ignored the range → restart this file
            offset = 0
        case 416:
            // Offset is at/past the end — stale or already-complete partial.
            // If it matches the expected size, promote it; otherwise restart.
            if let want = file.size, offset == want {
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: part, to: dest)
                onFileProgress(want)
                return
            }
            try? fm.removeItem(at: part)
            return try await fetch(repo: repoID, file: file, to: dest, onFileProgress: onFileProgress)
        default:
            throw DownloadError.badStatus(http.statusCode, file.path)
        }

        if !fm.fileExists(atPath: part.path) {
            fm.createFile(atPath: part.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var written = offset
        var buffer = Data()
        buffer.reserveCapacity(1 << 17)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 17 {   // flush every 128 KB
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                onFileProgress(written)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            onFileProgress(written)
        }
        try? handle.close()

        // Stream ended early (connection cut without an error)? Keep the
        // partial for the next resume and surface the failure.
        if let want = file.size, fileSize(at: part) != want {
            throw URLError(.networkConnectionLost)
        }
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: part, to: dest)
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int64) ?? 0
    }

    /// Fraction (0…1) of an interrupted download already on disk, from the
    /// `.part` partials plus completed files — so the UI can say "Resume —
    /// 62% already here" instead of a from-scratch "Download". `expectedBytes`
    /// comes from the catalog (cheap; no network round-trip).
    public static func partialFraction(repo repoID: String, expectedBytes: Int64) -> Double? {
        partialFraction(onDisk: diskUsage(repo: repoID), expectedBytes: expectedBytes)
    }

    /// Testable core of `partialFraction`.
    static func partialFraction(onDisk: Int64, expectedBytes: Int64) -> Double? {
        guard onDisk > 0, expectedBytes > 0 else { return nil }
        return min(Double(onDisk) / Double(expectedBytes), 0.99)
    }

    /// Remove a downloaded model from disk — weights, configs and any `.part`
    /// partial. Re-downloading later starts clean.
    public static func delete(repo repoID: String) throws {
        let dir = modelDirectory(forRepo: repoID)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Bytes this model currently occupies on disk (0 when absent).
    public static func diskUsage(repo repoID: String) -> Int64 {
        let dir = modelDirectory(forRepo: repoID)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(Int64(0)) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }
}
