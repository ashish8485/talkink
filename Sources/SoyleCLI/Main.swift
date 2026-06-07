import Foundation
import MLX
import MLXAudioSTT
import MLXAudioCore
import SoyleKit

// Söyle CLI — headless transcription + benchmarking harness for the Nemotron engine.
// usage: soyle-cli [--model REPO | --bf16] [--lang fr-FR] [--stream] AUDIO
@main
struct SoyleCLI {
    static func err(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }

    static func main() async {
        var model = SoyleModel.int8.repoID
        var language: String?
        var audioPath: String?
        var stream = false

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--model": if let v = it.next() { model = v }
            case "--bf16": model = SoyleModel.bf16.repoID
            case "--lang", "--language": if let v = it.next() { language = v }
            case "--stream": stream = true
            case "-h", "--help":
                err("usage: soyle-cli [--model REPO | --bf16] [--lang fr-FR] [--stream] AUDIO\n")
                return
            default: if !arg.hasPrefix("-") { audioPath = arg }
            }
        }

        guard let audioPath else {
            err("usage: soyle-cli [--model REPO | --bf16] [--lang fr-FR] [--stream] AUDIO\n")
            exit(2)
        }
        let url = URL(fileURLWithPath: (audioPath as NSString).expandingTildeInPath)

        do {
            err("Loading model: \(model)\n")
            let t0 = CFAbsoluteTimeGetCurrent()
            let asr = try await NemotronASRModel.fromPretrained(model)
            err(String(format: "  loaded in %.1fs\n", CFAbsoluteTimeGetCurrent() - t0))

            let (sr, audio) = try loadAudioArray(from: url, sampleRate: 16_000)
            let dur = Double(audio.shape[0]) / Double(sr)
            let params = STTGenerateParameters(language: language)

            if stream {
                err("--- streaming (lang=\(language ?? "auto")) ---\n")
                let t1 = CFAbsoluteTimeGetCurrent()
                for try await ev in asr.generateStream(audio: audio, generationParameters: params) {
                    if case .token(let tok) = ev { print(tok, terminator: ""); fflush(stdout) }
                }
                print()
                err(String(format: "[audio=%.1fs total=%.2fs]\n", dur, CFAbsoluteTimeGetCurrent() - t1))
            } else {
                let t1 = CFAbsoluteTimeGetCurrent()
                let out = asr.generate(audio: audio, generationParameters: params)
                let infer = CFAbsoluteTimeGetCurrent() - t1
                print(out.text.trimmingCharacters(in: .whitespacesAndNewlines))
                err(String(format: "[lang=%@ audio=%.1fs infer=%.2fs %.0fx RT]\n",
                           language ?? "auto", dur, infer, infer > 0 ? dur / infer : 0))
            }
        } catch {
            err("Error: \(error)\n")
            exit(1)
        }
    }
}
