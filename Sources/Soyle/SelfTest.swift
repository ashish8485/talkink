import Foundation
import AVFoundation
import SoyleKit

/// Headless verification used by scripts/CI: loads the model and transcribes a
/// file inside the assembled .app, so we can confirm the bundled Metal library
/// and weights work WITHOUT needing the GUI, microphone or Input Monitoring.
/// Usage: Söyle.app/Contents/MacOS/Soyle --selftest AUDIO.wav
enum SelfTest {
    static func run(audioPath: String) -> Never {
        guard !audioPath.isEmpty else {
            FileHandle.standardError.write(Data("[selftest] missing audio path\n".utf8))
            exit(2)
        }
        let url = URL(fileURLWithPath: (audioPath as NSString).expandingTildeInPath)
        let engine = TranscriptionEngine(model: .int8)
        final class LastPct: @unchecked Sendable { var value = -1 }
        let last = LastPct()
        engine.onDownloadProgress = { fraction in
            let pct = Int(fraction * 20) * 5   // 5% steps
            if pct != last.value {
                last.value = pct
                FileHandle.standardError.write(Data("[selftest] downloading model… \(pct)%\n".utf8))
            }
        }
        Task {
            do {
                try await engine.load()
                let r = try engine.transcribe(fileURL: url, language: nil)
                FileHandle.standardError.write(Data(String(
                    format: "[selftest] OK — audio=%.1fs infer=%.2fs %.0fx RT\n",
                    r.audioSeconds, r.inferSeconds, r.realtimeFactor).utf8))
                print(r.text)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("[selftest] ERROR: \(error)\n".utf8))
                exit(1)
            }
        }
        // Park the main thread as the main-queue executor: the engine's
        // download-progress handler is @MainActor — a blocked main thread
        // (semaphore) would deadlock the whole load.
        dispatchMain()
    }

    /// Records ~1.2s from the default microphone and reports the sample count —
    /// proves capture works (incl. the audio-input entitlement on hardened
    /// runtime builds). Usage: Söyle.app/Contents/MacOS/Soyle --mictest
    static func runMicTest() -> Never {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        FileHandle.standardError.write(Data("[mictest] mic TCC status=\(status.rawValue) (3=authorized)\n".utf8))
        let recorder = Recorder()
        do {
            try recorder.start()
        } catch {
            FileHandle.standardError.write(Data("[mictest] ERROR starting capture: \(error)\n".utf8))
            exit(1)
        }
        Thread.sleep(forTimeInterval: 1.2)
        let samples = recorder.stop()
        let rms = samples.isEmpty ? 0 : (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        FileHandle.standardError.write(Data(String(
            format: "[mictest] captured %d samples (%.2fs @16kHz) rms=%.5f\n",
            samples.count, Double(samples.count) / 16_000, rms).utf8))
        exit(samples.count > 8_000 ? 0 : 1)
    }
}
