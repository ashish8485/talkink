import Foundation
import MLX
import MLXAudioSTT
import MLXAudioCore
import SoyleKit

// Talkink CLI — headless transcription + multi-engine ASR benchmarking harness.
// usage: soyle-cli [--engine nemotron|qwen3|voxtral] [--model REPO | --bf16]
//                  [--lang fr-FR] [--stream] AUDIO [AUDIO…]
@main
struct SoyleCLI {
    static func err(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }

    static let usage = "usage: soyle-cli [--engine nemotron|qwen3|voxtral] [--model REPO | --bf16] [--lang fr-FR] [--stream] AUDIO [AUDIO…]\n"

    static func main() async {
        var engine = "nemotron"
        var modelOverride: String?
        var language: String?
        var audioPaths: [String] = []
        var stream = false

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--engine": if let v = it.next() { engine = v }
            case "--model": if let v = it.next() { modelOverride = v }
            case "--bf16": modelOverride = "mlx-community/nemotron-3.5-asr-streaming-0.6b"
            case "--lang", "--language": if let v = it.next() { language = v }
            case "--stream": stream = true
            case "-h", "--help":
                err(usage)
                return
            default: if !arg.hasPrefix("-") { audioPaths.append(arg) }
            }
        }

        guard !audioPaths.isEmpty else {
            err(usage)
            exit(2)
        }

        let model: String
        switch engine {
        case "qwen3":    model = modelOverride ?? "mlx-community/Qwen3-ASR-1.7B-8bit"
        case "voxtral":  model = modelOverride ?? "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"
        case "nemotron": model = modelOverride ?? "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
        default:
            err("unknown engine '\(engine)'\n\(usage)")
            exit(2)
        }

        do {
            err("Loading [\(engine)] \(model)\n")
            let t0 = CFAbsoluteTimeGetCurrent()
            let asr: any STTGenerationModel
            switch engine {
            case "qwen3":   asr = try await Qwen3ASRModel.fromPretrained(model)
            case "voxtral": asr = try await VoxtralRealtimeModel.fromPretrained(model)
            default:        asr = try await NemotronASRModel.fromPretrained(model)
            }
            err(String(format: "  loaded in %.1fs\n", CFAbsoluteTimeGetCurrent() - t0))

            for audioPath in audioPaths {
                let url = URL(fileURLWithPath: (audioPath as NSString).expandingTildeInPath)
                let (sr, audio) = try loadAudioArray(from: url, sampleRate: 16_000)
                let dur = Double(audio.shape[0]) / Double(sr)
                let params = STTGenerateParameters(language: language)
                if audioPaths.count > 1 { err("» \(url.lastPathComponent)\n") }

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
            }
        } catch {
            err("Error: \(error)\n")
            exit(1)
        }
    }
}
