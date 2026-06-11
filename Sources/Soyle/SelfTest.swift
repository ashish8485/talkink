import Foundation
import AVFoundation
import SoyleKit
import MLX

/// Headless verification used by scripts/CI: loads the model and transcribes a
/// file inside the assembled .app, so we can confirm the bundled Metal library
/// and weights work WITHOUT needing the GUI, microphone or Input Monitoring.
/// Usage: Talkink.app/Contents/MacOS/Soyle --selftest AUDIO.wav
enum SelfTest {
    static func run(audioPath: String) -> Never {
        guard !audioPath.isEmpty else {
            FileHandle.standardError.write(Data("[selftest] missing audio path\n".utf8))
            exit(2)
        }
        let url = URL(fileURLWithPath: (audioPath as NSString).expandingTildeInPath)
        // Self-test pins the lightest model: its job is validating the bundled
        // Metal library + pipeline, not transcription quality.
        let nemotron8 = ASRCatalog.option(forID: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")!
        let engine = TranscriptionEngine(model: nemotron8)
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
                // Exact-variant vocabulary pass only (the fuzzy layer needs the
                // main-thread spell checker — exercised in the app, not here).
                let corrected = Vocabulary.shared.apply(to: r.text)
                if corrected != r.text {
                    FileHandle.standardError.write(Data("[selftest] vocabulary: \"\(r.text)\" → \"\(corrected)\"\n".utf8))
                }
                print(corrected)
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

    /// Memory regression test: loads the biggest cached Qwen, switches to the
    /// smallest Nemotron, and proves the old weights actually left the process
    /// (MLX active memory + buffer cache + OS footprint). Guards the
    /// switchModel → clearCache contract.
    /// Usage: Talkink.app/Contents/MacOS/Soyle --memtest
    static func runMemTest() -> Never {
        func report(_ label: String) -> (active: Int, cache: Int) {
            let active = Memory.activeMemory
            let cache = Memory.cacheMemory
            FileHandle.standardError.write(Data(String(
                format: "[memtest] %@ — MLX active=%4d MB cache=%4d MB\n",
                label, active / 1_048_576, cache / 1_048_576).utf8))
            return (active, cache)
        }
        let big = ASRCatalog.option(forID: "mlx-community/Qwen3-ASR-1.7B-8bit")!
        let small = ASRCatalog.option(forID: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")!
        let engine = TranscriptionEngine(model: big)
        Task {
            do {
                try await engine.load()
                engine.warmUp()
                let loaded = report("after loading \(big.displayName)")
                engine.switchModel(to: small)
                try await engine.load()
                engine.warmUp()
                // switchModel clears the MLX cache asynchronously — give it a beat.
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let switched = report("after switching to \(small.displayName)")
                let releasedMB = (loaded.active - switched.active) / 1_048_576
                FileHandle.standardError.write(Data("[memtest] released \(releasedMB) MB of weights\n".utf8))
                // 1.7B-8bit weights ≈ 2.4 GB, nemotron ≈ 0.8 GB → at least ~1 GB
                // must have left MLX's active set, and the cache must be small.
                let ok = releasedMB > 1_000 && switched.cache < 500 * 1_048_576
                FileHandle.standardError.write(Data("[memtest] \(ok ? "OK" : "FAIL — old model still resident")\n".utf8))
                exit(ok ? 0 : 1)
            } catch {
                FileHandle.standardError.write(Data("[memtest] ERROR: \(error)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
    }

    /// Records ~1.2s from the default microphone and reports the sample count —
    /// proves capture works (incl. the audio-input entitlement on hardened
    /// runtime builds). Usage: Talkink.app/Contents/MacOS/Soyle --mictest
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
