#if SOYLE_DEVTOOLS
import AppKit
import SwiftUI
import Foundation

// A guided, hands-free recording studio used to build a real labelled voice
// dataset: VAD gate cases (speech in many conditions + non-speech) plus
// accuracy sentences in FR/EN/TR. It shows what to read (or when to stay
// silent), counts down, records via the SAME 16 kHz capture the app uses in
// production, stops automatically, and writes each clip + a manifest.json
// (reference text, language, condition, expected gate) for benchmarking and
// fine-tuning later. Launch: Soyle --record-dataset

// MARK: - Protocol

struct DatasetStep: Identifiable {
    enum Kind { case read, silent }
    let id: String
    let language: String        // BCP-47, or "" for non-speech
    let condition: String       // short chip
    let kind: Kind
    let directive: String       // what to do
    let text: String            // sentence to read (reference), or ""
    let seconds: Int
    let expectGate: String      // "speech" | "silence"
    let star: Bool              // core case

    init(id: String, language: String, condition: String, kind: Kind, directive: String,
         seconds: Int, expectGate: String, star: Bool, text: String) {
        self.id = id; self.language = language; self.condition = condition; self.kind = kind
        self.directive = directive; self.text = text; self.seconds = seconds
        self.expectGate = expectGate; self.star = star
    }
}

let datasetProtocol: [DatasetStep] = [
    // --- VAD gate: speech that MUST be accepted ---
    .init(id: "speech_loud_cont", language: "en-US", condition: "EN · loud + continuous", kind: .read,
          directive: "Lis FORT et SANS PAUSES, vite", seconds: 9, expectGate: "speech", star: true,
          text: "okay so today we refactor the login flow then we add the tests then we update the docs and we push everything before lunch no breaks let's go"),
    .init(id: "speech_soft", language: "fr-FR", condition: "FR · voix douce", kind: .read,
          directive: "Lis TRÈS DOUCEMENT, presque chuchoté", seconds: 6, expectGate: "speech", star: true,
          text: "Peux-tu m'envoyer le rapport commercial avant midi demain, s'il te plaît ?"),
    .init(id: "speech_noisy", language: "en-US", condition: "EN · bruit de fond", kind: .read,
          directive: "Mets de la musique ou la TV en fond, puis lis à voix normale", seconds: 7, expectGate: "speech", star: true,
          text: "Can you send me the quarterly report before noon tomorrow, please?"),
    .init(id: "speech_fr", language: "fr-FR", condition: "FR · normal", kind: .read,
          directive: "Pièce calme, voix normale", seconds: 6, expectGate: "speech", star: false,
          text: "Peux-tu m'envoyer le rapport commercial avant midi demain, s'il te plaît ?"),
    .init(id: "speech_en", language: "en-US", condition: "EN · normal", kind: .read,
          directive: "Pièce calme, voix normale", seconds: 6, expectGate: "speech", star: false,
          text: "Can you send me the quarterly report before noon tomorrow, please?"),
    .init(id: "speech_tr", language: "tr-TR", condition: "TR · normal", kind: .read,
          directive: "Pièce calme, voix normale", seconds: 6, expectGate: "speech", star: false,
          text: "Yarın öğleden önce çeyrek raporunu bana gönderebilir misin, lütfen?"),
    .init(id: "speech_short", language: "fr-FR", condition: "FR · mot court", kind: .read,
          directive: "Dis juste le mot affiché, puis attends", seconds: 3, expectGate: "speech", star: false,
          text: "Test."),
    .init(id: "speech_trailing", language: "fr-FR", condition: "FR · silence final", kind: .read,
          directive: "Lis la phrase, puis RESTE SILENCIEUX jusqu'à la fin", seconds: 8, expectGate: "speech", star: false,
          text: "Peux-tu m'envoyer le rapport commercial avant midi demain ?"),

    // --- VAD gate: non-speech that MUST be rejected ---
    .init(id: "silence_room", language: "", condition: "non-parole · silence", kind: .silent,
          directive: "RESTE SILENCIEUX, ne dis rien", seconds: 4, expectGate: "silence", star: true,
          text: ""),
    .init(id: "music_only", language: "", condition: "non-parole · musique", kind: .silent,
          directive: "Laisse la musique ou la TV jouer, NE PARLE PAS", seconds: 6, expectGate: "silence", star: true,
          text: ""),
    .init(id: "noise_only", language: "", condition: "non-parole · bruit", kind: .silent,
          directive: "Bruit de fond seul (ventilo, clim), NE PARLE PAS", seconds: 5, expectGate: "silence", star: true,
          text: ""),
    .init(id: "typing_only", language: "", condition: "non-parole · clavier", kind: .silent,
          directive: "TAPE AU CLAVIER, ne parle pas", seconds: 5, expectGate: "silence", star: false,
          text: ""),
    .init(id: "breath_cough", language: "", condition: "non-parole · souffle", kind: .silent,
          directive: "Respire, tousse, racle la gorge, SANS mots", seconds: 5, expectGate: "silence", star: false,
          text: ""),

    // --- Accuracy sentences (WER dataset), normal voice, quiet room ---
    .init(id: "acc_fr_1", language: "fr-FR", condition: "FR · précision", kind: .read,
          directive: "Voix normale, pièce calme", seconds: 8, expectGate: "speech", star: false,
          text: "Le train de seize heures trente part du quai numéro huit, n'oublie pas ton billet."),
    .init(id: "acc_fr_2", language: "fr-FR", condition: "FR · précision", kind: .read,
          directive: "Voix normale, pièce calme", seconds: 8, expectGate: "speech", star: false,
          text: "J'ai envoyé le devis par e-mail ce matin ; peux-tu le valider avant vendredi ?"),
    .init(id: "acc_en_1", language: "en-US", condition: "EN · précision", kind: .read,
          directive: "Voix normale, pièce calme", seconds: 8, expectGate: "speech", star: false,
          text: "The meeting is moved to three forty-five, and we need the slides ready by then."),
    .init(id: "acc_en_2", language: "en-US", condition: "EN · précision", kind: .read,
          directive: "Voix normale, pièce calme", seconds: 8, expectGate: "speech", star: false,
          text: "Please review pull request number forty-two and merge it if the tests pass."),
    .init(id: "acc_tr_1", language: "tr-TR", condition: "TR · précision", kind: .read,
          directive: "Voix normale, pièce calme", seconds: 8, expectGate: "speech", star: false,
          text: "Toplantı saat üç buçukta başlayacak, lütfen sunumu hazırla."),
    .init(id: "acc_tr_2", language: "tr-TR", condition: "TR · précision", kind: .read,
          directive: "Voix normale, pièce calme", seconds: 8, expectGate: "speech", star: false,
          text: "Faturayı bu sabah gönderdim; cuma gününe kadar onaylar mısın?"),
]

// MARK: - WAV writer (16 kHz mono PCM16)

enum WAV {
    static func write16kMono(_ samples: [Float], to url: URL) throws {
        let sr: UInt32 = 16_000, channels: UInt16 = 1, bits: UInt16 = 16
        let blockAlign = channels * bits / 8
        let byteRate = sr * UInt32(blockAlign)
        let dataBytes = UInt32(samples.count) * UInt32(blockAlign)
        var d = Data()
        func a(_ s: String) { d.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        a("RIFF"); u32(36 + dataBytes); a("WAVE")
        a("fmt "); u32(16); u16(1); u16(channels); u32(sr); u32(byteRate); u16(blockAlign); u16(bits)
        a("data"); u32(dataBytes)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32_767)
            var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        try d.write(to: url)
    }
}

// MARK: - Model

final class RecordingStudioModel: ObservableObject {
    enum Phase: Equatable { case ready, countingDown(Int), recording(Int), saved }

    @Published var index = 0
    @Published var phase: Phase = .ready
    @Published var level: Float = 0
    @Published var savedCount = 0
    @Published var errorMessage: String?

    let outDir: URL
    private let recorder = Recorder()
    private var ticker: Timer?
    private var entries: [String: [String: Any]] = [:]

    var step: DatasetStep { datasetProtocol[min(index, datasetProtocol.count - 1)] }
    var total: Int { datasetProtocol.count }
    var isDone: Bool { index >= total }

    init() {
        outDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("talkink-dataset")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        recorder.onLevel = { [weak self] lvl in DispatchQueue.main.async { self?.level = lvl } }
    }

    func startClip() {
        guard phase == .ready || phase == .saved else { return }
        errorMessage = nil
        phase = .countingDown(3)
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        switch phase {
        case .countingDown(let n):
            if n > 1 { phase = .countingDown(n - 1) } else { beginRecording() }
        case .recording(let r):
            if r > 1 { phase = .recording(r - 1) } else { finishRecording() }
        default:
            break
        }
    }

    private func beginRecording() {
        do {
            try recorder.start()
            // Read clips get a generous cap so you are never rushed; click
            // "J'ai fini" to stop early. Silent clips auto-stop on their timer.
            let dur = step.kind == .read ? max(step.seconds, 25) : step.seconds
            phase = .recording(dur)
        } catch {
            ticker?.invalidate(); ticker = nil
            errorMessage = "Micro indisponible: \(error.localizedDescription)"
            phase = .ready
        }
    }

    private func finishRecording() {
        ticker?.invalidate(); ticker = nil
        let samples = recorder.stop()
        level = 0
        let s = step
        let file = String(format: "%02d_%@.wav", index + 1, s.id)
        let url = outDir.appendingPathComponent(file)
        do { try WAV.write16kMono(samples, to: url) }
        catch { errorMessage = "Écriture échouée: \(error.localizedDescription)"; phase = .ready; return }
        entries[s.id] = [
            "file": file, "id": s.id, "language": s.language, "condition": s.condition,
            "kind": s.kind == .read ? "read" : "silent", "referenceText": s.text,
            "seconds": s.seconds, "expectGate": s.expectGate,
            "samples": samples.count, "durationSec": Double(samples.count) / 16_000.0,
        ]
        writeManifest()
        savedCount = entries.count
        phase = .saved
    }

    private func writeManifest() {
        let ordered = datasetProtocol.compactMap { entries[$0.id] }
        guard let data = try? JSONSerialization.data(withJSONObject: ordered, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: outDir.appendingPathComponent("manifest.json"))
    }

    func stopNow() { if case .recording = phase { finishRecording() } }
    func reRecord() { phase = .ready }
    func skip() { advance() }
    func next() { advance() }
    private func advance() {
        ticker?.invalidate(); ticker = nil
        if index < total - 1 { index += 1; phase = .ready } else { index = total }
        objectWillChange.send()
    }
}

// MARK: - View

struct RecordingStudioView: View {
    @ObservedObject var model: RecordingStudioModel

    var body: some View {
        Group {
            if model.isDone { doneView } else { activeView }
        }
        .frame(minWidth: 760, minHeight: 600)
        .background(Color(white: 0.10))
    }

    private var activeView: some View {
        let step = model.step
        return VStack(spacing: 22) {
            header(step)
            Spacer(minLength: 0)
            instructionCard(step)
            statusArea(step)
            Spacer(minLength: 0)
            controls
            meter
        }
        .padding(30)
        .foregroundStyle(.white)
    }

    private func header(_ step: DatasetStep) -> some View {
        HStack {
            Text("Clip \(model.index + 1) / \(model.total)")
                .font(.headline).foregroundStyle(.secondary)
            if step.star {
                Text("★ cœur").font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.nvidia.opacity(0.25)).clipShape(Capsule())
            }
            Spacer()
            Text(step.condition)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(white: 0.18)).clipShape(Capsule())
            Text("attendu: \(step.expectGate == "speech" ? "PAROLE" : "silence")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func instructionCard(_ step: DatasetStep) -> some View {
        VStack(spacing: 16) {
            Text(step.kind == .read ? "LIS À VOIX HAUTE" : "RESTE SILENCIEUX")
                .font(.system(size: 16, weight: .bold)).tracking(2)
                .foregroundStyle(step.kind == .read ? Color.nvidia : Color.orange)
            Text(step.directive)
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if step.kind == .read {
                Text(step.text)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func statusArea(_ step: DatasetStep) -> some View {
        switch model.phase {
        case .ready:
            Text(model.errorMessage ?? "Prépare la condition, puis démarre.")
                .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.orange)
                .frame(height: 70)
        case .countingDown(let n):
            Text("\(n)").font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                .frame(height: 70)
        case .recording(let r):
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Circle().fill(.red).frame(width: 14, height: 14)
                    Text("Enregistrement… \(r)s")
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(.red)
                }
                if step.kind == .read {
                    Text("Lis tranquillement, puis clique « J'ai fini ✓ » (ou Entrée).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.frame(height: 70)
        case .saved:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.nvidia)
                Text("Enregistré (\(model.savedCount)/\(model.total)).")
            }.font(.title3).frame(height: 70)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .ready:
            HStack(spacing: 14) {
                Button("Démarrer ce clip ▶") { model.startClip() }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                Button("Passer") { model.skip() }.controlSize(.large)
            }
        case .countingDown:
            Text("…").foregroundStyle(.secondary).frame(height: 36)
        case .recording:
            Button("J'ai fini ✓ (stop)") { model.stopNow() }
                .keyboardShortcut(.defaultAction).controlSize(.large)
        case .saved:
            HStack(spacing: 14) {
                Button("Refaire") { model.reRecord() }.controlSize(.large)
                Button(model.index < model.total - 1 ? "Suivant ▶" : "Terminer ▶") { model.next() }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
    }

    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.2))
                RoundedRectangle(cornerRadius: 4).fill(Color.nvidia)
                    .frame(width: geo.size.width * CGFloat(min(1, model.level * 3)))
            }
        }
        .frame(height: 8)
        .opacity({ if case .recording = model.phase { return 1 } else { return 0.25 } }())
    }

    private var doneView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Color.nvidia)
            Text("Terminé").font(.largeTitle.bold())
            Text("\(model.savedCount) clips enregistrés dans:\n~/talkink-dataset")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("manifest.json écrit (texte de référence + condition par clip).")
                .font(.callout).foregroundStyle(.secondary)
            Button("Fermer") { NSApp.terminate(nil) }.controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white).background(Color(white: 0.10))
    }
}

// MARK: - Standalone app delegate for the studio window

final class RecordingStudioAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let model = RecordingStudioModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Talkink Recording Studio"
        w.center()
        w.contentView = NSHostingView(rootView: RecordingStudioView(model: model))
        w.makeKeyAndOrderFront(nil)
        window = w
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
