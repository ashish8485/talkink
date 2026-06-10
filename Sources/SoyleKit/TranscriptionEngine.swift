import Foundation
import MLX
import MLXAudioSTT
import MLXAudioCore
import HuggingFace

/// Which Nemotron 3.5 ASR weights to load. 8-bit is the default (smaller, faster,
/// quality on par with bf16 on this hardware); bf16 is the max-precision fallback.
public enum SoyleModel: String, CaseIterable, Sendable {
    case int8 = "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
    case bf16 = "mlx-community/nemotron-3.5-asr-streaming-0.6b"

    public var repoID: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .int8: return "8-bit"
        case .bf16: return "bf16"
        }
    }

    public var menuLabel: String {
        switch self {
        case .int8: return "8-bit (fast, recommended)"
        case .bf16: return "bf16 (max accuracy)"
        }
    }

    /// Approximate one-time download size, for first-run UI.
    public var approxSize: String {
        switch self {
        case .int8: return "~756 MB"
        case .bf16: return "~1.2 GB"
        }
    }
}

/// Result of one transcription.
public struct SoyleTranscription: Sendable {
    public let text: String
    public let language: String?
    public let audioSeconds: Double
    public let inferSeconds: Double
    public var realtimeFactor: Double { inferSeconds > 0 ? audioSeconds / inferSeconds : 0 }
}

public enum SoyleError: Error, LocalizedError {
    case modelNotLoaded
    case audioLoadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "The model isn't loaded yet."
        case .audioLoadFailed(let p): return "Audio loading failed: \(p)"
        }
    }
}

/// Loads the Nemotron model once and transcribes 16 kHz mono audio.
/// Call `load()` (async) before transcribing. Safe to call transcribe from a
/// background queue; MLX evaluation is internally serialized.
public final class TranscriptionEngine: @unchecked Sendable {
    public private(set) var model: SoyleModel
    private var asr: NemotronASRModel?
    private let lock = NSLock()
    private let inferLock = NSLock()   // serialize MLX inference (warmUp vs transcribe must not overlap)

    /// Called on the main actor with 0…1 progress while the model downloads
    /// (first run, ~756 MB). Not called when the cache is already warm.
    public var onDownloadProgress: (@MainActor @Sendable (Double) -> Void)?

    public init(model: SoyleModel = .int8) {
        self.model = model
    }

    public var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return asr != nil
    }

    /// Download (first run) + load weights into memory. Idempotent per model.
    public func load() async throws {
        if isLoaded { return }
        let target = currentTargetModel()
        try await predownloadReportingProgress(target)
        let loaded = try await NemotronASRModel.fromPretrained(target.repoID)
        install(loaded, ifStillTargeting: target)
    }

    /// Resolve (download on first run) the weights with byte-level progress —
    /// `fromPretrained` has no progress hook, so we pre-warm the same cache it
    /// reads from. No-op cost when already cached.
    private func predownloadReportingProgress(_ target: SoyleModel) async throws {
        guard let onDownloadProgress, let repoID = Repo.ID(rawValue: target.repoID) else { return }
        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
        let client: HubClient = (token?.isEmpty == false)
            ? HubClient(host: HubClient.defaultHost, bearerToken: token, cache: .default)
            : HubClient(cache: .default)
        _ = try await ModelUtils.resolveOrDownloadModel(
            client: client,
            cache: .default,
            repoID: repoID,
            requiredExtension: "safetensors",
            progressHandler: { progress in
                let f = progress.fractionCompleted
                if f < 1.0 { onDownloadProgress(f) }
            }
        )
    }

    private func currentTargetModel() -> SoyleModel {
        lock.lock(); defer { lock.unlock() }
        return model
    }

    private func install(_ loaded: NemotronASRModel, ifStillTargeting target: SoyleModel) {
        lock.lock(); defer { lock.unlock() }
        // A switchModel() may have raced this load — never install stale weights.
        if model == target { asr = loaded }
    }

    /// Run a tiny dummy inference to compile/warm the Metal pipeline, so the
    /// first real transcription isn't penalised by ~2-3s of shader warm-up.
    public func warmUp() {
        guard let asr = currentModel() else { return }
        let silence = [Float](repeating: 0, count: 8_000) // 0.5s @ 16kHz
        inferLock.lock(); defer { inferLock.unlock() }
        _ = asr.generate(audio: MLXArray(silence), generationParameters: STTGenerateParameters(language: nil))
    }

    /// Switch model weights; the new weights load on the next `load()`.
    public func switchModel(to newModel: SoyleModel) {
        guard newModel != model else { return }
        lock.lock(); model = newModel; asr = nil; lock.unlock()
    }

    private func currentModel() -> NemotronASRModel? {
        lock.lock(); defer { lock.unlock() }
        return asr
    }

    /// Transcribe an audio file (any format/rate — resampled to 16 kHz mono).
    /// `language` is a BCP-47 prompt key ("en-US", "fr-FR") or nil for auto.
    public func transcribe(fileURL: URL, language: String?) throws -> SoyleTranscription {
        guard let asr = currentModel() else { throw SoyleError.modelNotLoaded }
        let sr: Int
        let audio: MLXArray
        do {
            (sr, audio) = try loadAudioArray(from: fileURL, sampleRate: 16_000)
        } catch {
            throw SoyleError.audioLoadFailed(fileURL.path)
        }
        return run(asr: asr, audio: audio, sampleRate: sr, language: language)
    }

    /// Transcribe in-memory float samples already at 16 kHz mono.
    public func transcribe(samples: [Float], language: String?) throws -> SoyleTranscription {
        guard let asr = currentModel() else { throw SoyleError.modelNotLoaded }
        return run(asr: asr, audio: MLXArray(samples), sampleRate: 16_000, language: language)
    }

    private func run(asr: NemotronASRModel, audio: MLXArray, sampleRate: Int, language: String?) -> SoyleTranscription {
        let frames = audio.shape.first ?? 0
        let duration = Double(frames) / Double(sampleRate)
        // Nothing meaningful to transcribe in < 0.1s — avoids feeding a near-empty
        // array into MLX (untested edge in generate()).
        guard frames >= 1_600 else {
            return SoyleTranscription(text: "", language: language, audioSeconds: duration, inferSeconds: 0)
        }
        let params = STTGenerateParameters(language: language)
        let t0 = CFAbsoluteTimeGetCurrent()
        inferLock.lock()
        let out = asr.generate(audio: audio, generationParameters: params)
        inferLock.unlock()
        let infer = CFAbsoluteTimeGetCurrent() - t0
        return SoyleTranscription(
            text: out.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            audioSeconds: duration,
            inferSeconds: infer
        )
    }
}
