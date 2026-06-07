import Foundation
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
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task {
            do {
                try await engine.load()
                let r = try engine.transcribe(fileURL: url, language: nil)
                FileHandle.standardError.write(Data(String(
                    format: "[selftest] OK — audio=%.1fs infer=%.2fs %.0fx RT\n",
                    r.audioSeconds, r.inferSeconds, r.realtimeFactor).utf8))
                print(r.text)
            } catch {
                FileHandle.standardError.write(Data("[selftest] ERROR: \(error)\n".utf8))
                code = 1
            }
            sem.signal()
        }
        sem.wait()
        exit(code)
    }
}
