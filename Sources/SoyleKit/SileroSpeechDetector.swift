import Foundation
import MLX
import MLXAudioCore
import MLXAudioVAD

/// Decodes an audio file exactly the way the engine does: 16 kHz mono float PCM.
public enum AudioLoader {
    public static func load16kMono(url: URL) throws -> [Float] {
        let (_, audio) = try loadAudioArray(from: url, sampleRate: 16_000)
        return audio.asArray(Float.self)
    }
}

/// Verdict from running Silero VAD over a buffer.
public struct SileroResult: Sendable, Equatable {
    public let speechSeconds: Double
    public let segments: Int
    /// Silero already filters by a minimum speech duration, so any returned
    /// segment means real speech was found.
    public var likelySpeech: Bool { segments > 0 }
}

/// Thin wrapper over the Silero VAD shipped by mlx-audio-swift (MLXAudioVAD).
/// Candidate replacement for the RMS-only `SpeechStats` gate in the
/// hallucination guard: a small neural net that tells speech from non-speech,
/// where RMS only measures loudness. The model is tiny (~309K params) and our
/// recorder already produces the 16 kHz mono it expects.
public final class SileroSpeechDetector {
    private let vad: SileroVAD
    private init(_ vad: SileroVAD) { self.vad = vad }

    public static func load(repo: String = "mlx-community/silero-vad") async throws -> SileroSpeechDetector {
        SileroSpeechDetector(try await SileroVAD.fromPretrained(repo))
    }

    public func analyze(samples: [Float], sampleRate: Int = 16_000) throws -> SileroResult {
        let audio = MLXArray(samples)
        let timestamps = try vad.getSpeechTimestamps(audio, sampleRate: sampleRate)
        let speechSamples = timestamps.reduce(0) { $0 + ($1.end - $1.start) }
        return SileroResult(speechSeconds: Double(speechSamples) / Double(sampleRate),
                            segments: timestamps.count)
    }
}

/// Resolves the single "did the user actually speak?" verdict for the
/// hallucination guard. Silero is authoritative when it ran; RMS `SpeechStats`
/// is the safety net for when Silero is unavailable (still loading, offline at
/// first run, or it errored). The guard keeps working no matter what.
public enum SpeechGate {
    public enum Source: String, Sendable, Equatable { case silero, rms }

    public struct Verdict: Sendable, Equatable {
        public let hasSpeech: Bool
        public let source: Source
        public init(hasSpeech: Bool, source: Source) {
            self.hasSpeech = hasSpeech
            self.source = source
        }
    }

    public static func resolve(silero: SileroResult?, rms: SpeechStats) -> Verdict {
        if let silero {
            return Verdict(hasSpeech: silero.likelySpeech, source: .silero)
        }
        return Verdict(hasSpeech: rms.likelySpeech, source: .rms)
    }
}
