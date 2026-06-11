import Foundation

/// Cheap energy-based speech detector over the captured 16 kHz samples.
/// Its single job: after an empty transcript, tell apart "the room was
/// silent" from "someone clearly spoke but the model produced nothing"
/// (typically a forced language that doesn't match the speech) — two cases
/// that must NOT show the same message.
public struct SpeechStats: Equatable, Sendable {
    public let duration: Double
    /// Loudest 25 ms frame (RMS).
    public let peakRMS: Float
    /// 20th-percentile frame RMS — the session's own background level, so the
    /// threshold adapts to quiet rooms and noisy fans alike.
    public let noiseFloor: Float
    /// Seconds spent meaningfully above the noise floor.
    public let activeSeconds: Double

    /// Tuned against synthetic fixtures (see SpeechStatsTests) and real mic
    /// levels (normal speech ≈ 0.05–0.3 RMS; idle rooms ≈ 0.001–0.01).
    public var likelySpeech: Bool {
        activeSeconds >= 0.25 && peakRMS >= 0.015
    }

    public static func analyze(samples: [Float], sampleRate: Int = 16_000) -> SpeechStats {
        let frameLength = max(1, sampleRate / 40)   // 25 ms frames
        let duration = Double(samples.count) / Double(sampleRate)
        guard samples.count >= frameLength else {
            return SpeechStats(duration: duration, peakRMS: 0, noiseFloor: 0, activeSeconds: 0)
        }
        var frames: [Float] = []
        frames.reserveCapacity(samples.count / frameLength + 1)
        var index = 0
        while index + frameLength <= samples.count {
            var sum: Float = 0
            for i in index..<(index + frameLength) { sum += samples[i] * samples[i] }
            frames.append((sum / Float(frameLength)).squareRoot())
            index += frameLength
        }
        let sorted = frames.sorted()
        let noiseFloor = sorted[frames.count / 5]
        let peak = sorted[frames.count - 1]
        // Speech sits well above the session's own background; the absolute
        // floor keeps electrical hiss from counting in dead-quiet rooms.
        let threshold = max(0.012, noiseFloor * 3)
        let activeFrames = frames.filter { $0 >= threshold }.count
        let frameSeconds = Double(frameLength) / Double(sampleRate)
        return SpeechStats(
            duration: duration,
            peakRMS: peak,
            noiseFloor: noiseFloor,
            activeSeconds: Double(activeFrames) * frameSeconds
        )
    }
}
