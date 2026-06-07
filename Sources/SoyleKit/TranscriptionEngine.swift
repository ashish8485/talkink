import Foundation
import MLX
import MLXAudioSTT
import MLXAudioCore

/// Which Nemotron 3.5 ASR weights to load. 8-bit is the default (smaller, faster,
/// quality on par with bf16 on this hardware); bf16 is the max-precision fallback.
public enum SoyleModel: String, CaseIterable, Sendable {
    case int8 = "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
    case bf16 = "mlx-community/nemotron-3.5-asr-streaming-0.6b"

    public var repoID: String { rawValue }

    public var label: String {
        switch self {
        case .int8: return "8-bit (recommandé)"
        case .bf16: return "bf16 (précision max)"
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
        case .modelNotLoaded: return "Le modèle n'est pas encore chargé."
        case .audioLoadFailed(let p): return "Échec du chargement audio : \(p)"
        }
    }
}

/// Loads the Nemotron model once and transcribes 16 kHz mono audio.
/// Thread-safety: keep one instance; call `load()` before `transcribe...`.
public final class TranscriptionEngine: @unchecked Sendable {
    public private(set) var model: SoyleModel
    private var asr: NemotronASRModel?

    public init(model: SoyleModel = .int8) {
        self.model = model
    }

    public var isLoaded: Bool { asr != nil }

    /// Download (first run) + load weights into memory. Idempotent per model.
    public func load() async throws {
        if asr != nil { return }
        asr = try await NemotronASRModel.fromPretrained(model.repoID)
    }

    /// Switch model weights, reloading on next `load()`.
    public func switchModel(to newModel: SoyleModel) {
        guard newModel != model else { return }
        model = newModel
        asr = nil
    }

    /// Transcribe an audio file (any format/rate — resampled to 16 kHz mono).
    /// `language` is a BCP-47 prompt key ("en-US", "fr-FR") or nil for auto.
    public func transcribe(fileURL: URL, language: String?) throws -> SoyleTranscription {
        guard let asr else { throw SoyleError.modelNotLoaded }
        let (sr, audio): (Int, MLXArray)
        do {
            (sr, audio) = try loadAudioArray(from: fileURL, sampleRate: 16_000)
        } catch {
            throw SoyleError.audioLoadFailed(fileURL.path)
        }
        return run(asr: asr, audio: audio, sampleRate: sr, language: language)
    }

    /// Transcribe in-memory float samples already at 16 kHz mono.
    public func transcribe(samples: [Float], language: String?) throws -> SoyleTranscription {
        guard let asr else { throw SoyleError.modelNotLoaded }
        return run(asr: asr, audio: MLXArray(samples), sampleRate: 16_000, language: language)
    }

    private func run(asr: NemotronASRModel, audio: MLXArray, sampleRate: Int, language: String?) -> SoyleTranscription {
        let duration = Double(audio.shape[0]) / Double(sampleRate)
        let params = STTGenerateParameters(language: language)
        let t0 = CFAbsoluteTimeGetCurrent()
        let out = asr.generate(audio: audio, generationParameters: params)
        let infer = CFAbsoluteTimeGetCurrent() - t0
        return SoyleTranscription(
            text: out.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            audioSeconds: duration,
            inferSeconds: infer
        )
    }
}
