import Foundation
import AVFoundation

/// Captures the microphone during a push-to-talk window and produces
/// 16 kHz mono Float32 samples (what Nemotron expects). AVAudioConverter
/// handles resampling (48k/44.1k → 16k) and downmix in one pass.
final class Recorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private var samples: [Float] = []
    private let sampleLock = NSLock()
    private var isRecording = false

    /// Called ~frequently on a background thread with a 0...1 input level (RMS),
    /// for the live waveform/meter. Always re-dispatched to main by the consumer.
    var onLevel: (Float) -> Void = { _ in }

    var recording: Bool { isRecording }

    /// Start capturing. Throws if the engine can't start (e.g. mic denied).
    func start() throws {
        guard !isRecording else { return }
        sampleLock.lock(); samples.removeAll(keepingCapacity: true); sampleLock.unlock()

        let input = engine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)
        // Guard against a 0 Hz "no device" format that throws in installTap.
        guard hwFormat.sampleRate > 0 else {
            throw NSError(domain: "Soyle.Recorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Aucun périphérique d'entrée audio disponible."])
        }
        converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, hwFormat: hwFormat)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stop capturing and return the accumulated 16 kHz mono samples.
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        sampleLock.lock(); let out = samples; samples.removeAll(); sampleLock.unlock()
        return out
    }

    private func process(buffer: AVAudioPCMBuffer, hwFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / hwFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard capacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        var err: NSError?
        let result = converter.convert(to: out, error: &err, withInputFrom: inputBlock)
        guard result == .haveData, out.frameLength > 0, let ch = out.floatChannelData else { return }

        let n = Int(out.frameLength)
        let ptr = ch[0]
        // RMS level for the meter.
        var sum: Float = 0
        for i in 0..<n { sum += ptr[i] * ptr[i] }
        let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
        onLevel(min(1, rms * 6)) // scale for visibility

        sampleLock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: n))
        sampleLock.unlock()
    }
}
