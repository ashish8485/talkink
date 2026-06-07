import AppKit
import AVFoundation
import Combine
import SoyleKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    enum AppState: Equatable {
        case loadingModel
        case ready
        case recording
        case transcribing
        case needsInputMonitoring
    }

    private let settings = SettingsStore.shared
    private let engine = TranscriptionEngine(model: SettingsStore.shared.model)
    private let ptt = PushToTalk(key: SettingsStore.shared.pttKey)
    private let recorder = Recorder()
    private let overlay = OverlayController()
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)

    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var state: AppState = .loadingModel { didSet { updateMenu(); updateStatusIcon() } }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        recorder.onLevel = { [weak self] lvl in self?.overlay.updateLevel(lvl) }
        ptt.onStart = { [weak self] in self?.startRecording() }
        ptt.onStop = { [weak self] in self?.stopRecording() }

        observeSettings()
        requestPermissionsThenStart()
        loadModel()

        UpdateChecker.shared.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
        UpdateChecker.shared.check()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ptt.stop()
        _ = recorder.stop()
    }

    // MARK: Startup helpers

    private func requestPermissionsThenStart() {
        // Microphone: prompt once on first launch.
        if AVCaptureDeviceStatusIsUndetermined() {
            Permissions.requestMicrophone { _ in }
        }
        // Input Monitoring: needed for the global tap.
        if ptt.start() {
            state = .loadingModel // will flip to .ready once model loads
        } else {
            state = .needsInputMonitoring
        }
        // First run, or push-to-talk permission still missing → show onboarding/settings.
        if !settings.hasOnboarded || !Permissions.hasInputMonitoring {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
        settings.hasOnboarded = true
    }

    private func loadModel() {
        Task { @MainActor in
            do {
                try await engine.load()
                await Task.detached(priority: .userInitiated) { [engine] in engine.warmUp() }.value
                if state != .needsInputMonitoring { state = .ready }
                else { updateMenu() }
            } catch {
                overlay.show(.error("Échec du chargement du modèle"), autoHideAfter: 3)
            }
        }
    }

    private func observeSettings() {
        settings.$model
            .dropFirst()
            .sink { [weak self] newModel in self?.reloadModel(newModel) }
            .store(in: &cancellables)
        settings.$pttKey
            .dropFirst()
            .sink { [weak self] key in
                guard let self else { return }
                self.ptt.stop()
                self.ptt.setKey(key)
                _ = self.ptt.start()
            }
            .store(in: &cancellables)
    }

    private func reloadModel(_ newModel: SoyleModel) {
        engine.switchModel(to: newModel)
        state = .loadingModel
        Task { @MainActor in
            do {
                try await engine.load()
                await Task.detached(priority: .userInitiated) { [engine] in engine.warmUp() }.value
                state = .ready
            } catch {
                overlay.show(.error("Échec du chargement du modèle"), autoHideAfter: 3)
            }
        }
    }

    // MARK: Recording flow

    private func startRecording() {
        guard state == .ready else {
            if state == .loadingModel {
                overlay.show(.error("Modèle en cours de chargement…"), autoHideAfter: 1.5)
            } else if state == .needsInputMonitoring {
                promptInputMonitoring()
            }
            return
        }
        guard Permissions.hasMicrophone else {
            if Permissions.microphoneDenied {
                overlay.show(.error("Micro refusé — voir Réglages"), autoHideAfter: 2.5)
                Permissions.openMicrophoneSettings()
            } else {
                Permissions.requestMicrophone { _ in }
            }
            return
        }
        do {
            try recorder.start()
            state = .recording
            overlay.show(.recording)
            playSound(start: true)
        } catch {
            overlay.show(.error("Micro indisponible"), autoHideAfter: 2)
        }
    }

    private func stopRecording() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        playSound(start: false)

        // Ignore accidental taps (< 0.25s of audio).
        guard samples.count >= 4_000 else {
            state = .ready
            overlay.hide()
            return
        }

        state = .transcribing
        overlay.show(.transcribing)
        let lang = settings.language.engineCode

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.engine.transcribe(samples: samples, language: lang)
                DispatchQueue.main.async {
                    let text = result.text
                    if !text.isEmpty {
                        Clipboard.copy(text)                                  // always: paste manually with ⌘V
                        HistoryStore.shared.add(text: text, language: lang)   // always retrievable in the app
                        if self.settings.autoPaste { AutoPaster.paste() }     // and auto-insert at the cursor
                    }
                    self.overlay.show(.done(text), autoHideAfter: text.isEmpty ? 1.2 : 1.0)
                    self.state = .ready
                }
            } catch {
                DispatchQueue.main.async {
                    self.overlay.show(.error("Erreur de transcription"), autoHideAfter: 2)
                    self.state = .ready
                }
            }
        }
    }

    private func playSound(start: Bool) {
        guard settings.playSounds else { return }
        NSSound(named: start ? "Tink" : "Pop")?.play()
    }

    // MARK: Status item + menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        updateMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch state {
        case .recording: symbol = "mic.fill"
        case .transcribing: symbol = "waveform"
        case .needsInputMonitoring: symbol = "exclamationmark.triangle.fill"
        default: symbol = "mic"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Söyle")
        button.image?.isTemplate = (state != .recording)
        button.contentTintColor = (state == .recording) ? .nvidia : nil
    }

    private func updateMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if state == .needsInputMonitoring {
            menu.addItem(item("Autoriser « Surveillance des saisies »…", #selector(promptInputMonitoringMenu)))
            menu.addItem(.separator())
        }

        if let up = UpdateChecker.shared.latest {
            let mi = item("⬆ Nouvelle version v\(up.version)…", #selector(openUpdate(_:)))
            mi.representedObject = up.url
            menu.addItem(mi)
            menu.addItem(.separator())
        }

        // Language submenu
        let langItem = NSMenuItem(title: "Langue : \(settings.language.displayName)", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in SoyleLanguage.allCases {
            let mi = item(lang.displayName, #selector(selectLanguage(_:)))
            mi.representedObject = lang.rawValue
            mi.state = (lang == settings.language) ? .on : .off
            langMenu.addItem(mi)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // Model submenu
        let modelItem = NSMenuItem(title: "Modèle : \(settings.model.shortLabel)", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for m in SoyleModel.allCases {
            let mi = item(m.menuLabel, #selector(selectModel(_:)))
            mi.representedObject = m.rawValue
            mi.state = (m == settings.model) ? .on : .off
            modelMenu.addItem(mi)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        // Key submenu
        let keyItem = NSMenuItem(title: "Touche : \(settings.pttKey.displayName)", action: nil, keyEquivalent: "")
        let keyMenu = NSMenu()
        for k in PushToTalk.Key.allCases {
            let mi = item(k.displayName, #selector(selectKey(_:)))
            mi.representedObject = k.rawValue
            mi.state = (k == settings.pttKey) ? .on : .off
            keyMenu.addItem(mi)
        }
        keyItem.submenu = keyMenu
        menu.addItem(keyItem)

        let sounds = item("Sons de retour", #selector(toggleSounds))
        sounds.state = settings.playSounds ? .on : .off
        menu.addItem(sounds)

        menu.addItem(.separator())
        menu.addItem(item("Ouvrir Söyle (historique, réglages)…", #selector(openSettings), key: ","))
        menu.addItem(item("À propos de Söyle", #selector(about)))
        menu.addItem(.separator())
        menu.addItem(item("Quitter Söyle", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func statusLine() -> String {
        switch state {
        case .loadingModel: return "⏳ Chargement du modèle…"
        case .ready: return "● Prêt — maintiens \(settings.pttKey.displayName)"
        case .recording: return "🎙 Enregistrement…"
        case .transcribing: return "✍️ Transcription…"
        case .needsInputMonitoring: return "⚠️ Autorisation requise"
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    // MARK: Menu actions

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lang = SoyleLanguage(rawValue: raw) {
            settings.language = lang
            updateMenu()
        }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = SoyleModel(rawValue: raw) {
            settings.model = m
            updateMenu()
        }
    }

    @objc private func selectKey(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? Int, let k = PushToTalk.Key(rawValue: raw) {
            settings.pttKey = k
            updateMenu()
        }
    }

    @objc private func toggleSounds() { settings.playSounds.toggle(); updateMenu() }

    @objc private func openSettings() { settingsWindowController.show() }

    @objc private func openUpdate(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func promptInputMonitoringMenu() { openSettings() }

    private func promptInputMonitoring() { openSettings() }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Söyle"
        alert.informativeText = "Dictée vocale locale (NVIDIA Nemotron 3.5 ASR via MLX).\nMaintiens \(settings.pttKey.displayName), parle, relâche — le texte est copié."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

private func AVCaptureDeviceStatusIsUndetermined() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
}
