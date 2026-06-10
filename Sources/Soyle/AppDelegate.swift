import AppKit
import AVFoundation
import Combine
import SoyleKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    enum AppState: Equatable {
        case loadingModel(progress: Int?)   // percent while downloading (first run), nil while loading weights
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
    private var armTimer: Timer?
    private var modelLoadFailed = false
    private var pendingStop: DispatchWorkItem?   // release-grace timer (tail capture)
    private var dictationGeneration = 0          // ignore stale transcription completions
    private var state: AppState = .loadingModel(progress: nil) { didSet { updateMenu(); updateStatusIcon() } }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        recorder.onLevel = { [weak self] lvl in self?.overlay.updateLevel(lvl) }
        ptt.onStart = { [weak self] in self?.startRecording() }
        ptt.onStop = { [weak self] in self?.stopRecording() }
        engine.onDownloadProgress = { [weak self] fraction in
            guard let self else { return }
            let pct = min(99, Int(fraction * 100))
            // Only meaningful while we're in the loading state (first run).
            if case .loadingModel(let current) = self.state, current != pct {
                self.state = .loadingModel(progress: pct)
            }
        }

        observeSettings()
        requestPermissionsThenStart()
        loadModel()

        Updater.shared.automaticallyChecksForUpdates = settings.checkForUpdates
        settings.$checkForUpdates
            .dropFirst()
            .sink { Updater.shared.automaticallyChecksForUpdates = $0 }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ptt.stop()
        pendingStop?.cancel()
        _ = recorder.stop()
        armTimer?.invalidate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        tryRearm()
        // Recover a failed first-run model load (e.g. offline) without a relaunch.
        if modelLoadFailed, !engine.isLoaded {
            loadModel()
        }
    }

    // Re-arm the push-to-talk tap once Input Monitoring is granted in-session,
    // so the user doesn't have to relaunch.
    private func startArmTimer() {
        armTimer?.invalidate()
        armTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tryRearm()
        }
    }

    private func tryRearm() {
        guard state == .needsInputMonitoring, Permissions.hasInputMonitoring else { return }
        if ptt.start() {
            armTimer?.invalidate(); armTimer = nil
            state = engine.isLoaded ? .ready : .loadingModel(progress: nil)
        }
    }

    // MARK: Startup helpers

    private func requestPermissionsThenStart() {
        // Microphone: prompt once on first launch.
        if AVCaptureDeviceStatusIsUndetermined() {
            Permissions.requestMicrophone { _ in }
        }
        // Input Monitoring: needed for the global tap.
        if ptt.start() {
            state = .loadingModel(progress: nil) // will flip to .ready once model loads
        } else {
            state = .needsInputMonitoring
            startArmTimer()       // auto-recover once the grant lands (no relaunch needed)
        }
        // First run, or push-to-talk permission still missing → show onboarding/settings.
        if !settings.hasOnboarded || !Permissions.hasInputMonitoring {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
        settings.hasOnboarded = true
    }

    private func loadModel() {
        modelLoadFailed = false
        Task { @MainActor in
            do {
                try await engine.load()
                await Task.detached(priority: .userInitiated) { [engine] in engine.warmUp() }.value
                // A concurrent model switch may have invalidated this load — only
                // a load whose weights are actually installed flips to .ready.
                if engine.isLoaded, state != .needsInputMonitoring { state = .ready }
                else { updateMenu() }
            } catch {
                modelLoadFailed = true
                overlay.show(.error("Load failed — will retry on next activation"), autoHideAfter: 3)
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
        // Leaving .recording without stopping the recorder would swallow the
        // PTT release in stopRecording's guard and leave the mic running.
        abortRecordingIfNeeded()
        engine.switchModel(to: newModel)
        state = .loadingModel(progress: nil)
        Task { @MainActor in
            do {
                try await engine.load()
                await Task.detached(priority: .userInitiated) { [engine] in engine.warmUp() }.value
                if engine.isLoaded { state = .ready }
            } catch {
                overlay.show(.error("Model failed to load"), autoHideAfter: 3)
            }
        }
    }

    // MARK: Recording flow

    private func startRecording() {
        // Re-pressed during the release-grace window: flush the previous
        // dictation now and start fresh.
        if let pending = pendingStop {
            pending.cancel(); pendingStop = nil
            finishStop()
            if state == .transcribing { state = .ready }
        }
        guard state == .ready else {
            if case .loadingModel(let pct) = state {
                overlay.show(.error(pct != nil ? "Downloading model…" : "Model is loading…"),
                             autoHideAfter: 1.5)
            } else if state == .needsInputMonitoring {
                promptInputMonitoring()
            }
            return
        }
        guard Permissions.hasMicrophone else {
            if Permissions.microphoneDenied {
                overlay.show(.error("Microphone denied — see Settings"), autoHideAfter: 2.5)
                Permissions.openMicrophoneSettings()
            } else {
                Permissions.requestMicrophone { _ in }
            }
            return
        }
        do {
            if recorder.recording { _ = recorder.stop() }  // defensive: stale session
            try recorder.start()
            state = .recording
            overlay.show(.recording)
            playSound(start: true)
        } catch {
            overlay.show(.error("Microphone unavailable"), autoHideAfter: 2)
        }
    }

    private func stopRecording() {
        guard state == .recording else {
            // Defensive: never leave the mic running (e.g. if a model switch
            // yanked us out of .recording mid-hold).
            if recorder.recording, pendingStop == nil { _ = recorder.stop() }
            return
        }
        playSound(start: false)
        state = .transcribing
        overlay.show(.transcribing)

        // Keep capturing a short tail: people release the key on the last word,
        // and the resampler buffers a few extra milliseconds.
        let work = DispatchWorkItem { [weak self] in self?.finishStop() }
        pendingStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func finishStop() {
        pendingStop = nil
        let samples = recorder.stop()

        // Ignore accidental taps (< 0.25s of speech + the 0.25s tail).
        guard samples.count >= 8_000 else {
            if state == .transcribing {
                state = .ready
                overlay.hide()
            }
            return
        }

        dictationGeneration += 1
        let gen = dictationGeneration
        let lang = settings.language.engineCode

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.engine.transcribe(samples: samples, language: lang)
                DispatchQueue.main.async {
                    let text = result.text
                    var pasted = false
                    if !text.isEmpty {
                        Clipboard.copy(text)                                  // always: paste manually with ⌘V
                        if AutoPaster.secureInputActive {
                            // Likely a password field — keep it out of the on-disk history.
                        } else {
                            HistoryStore.shared.add(text: text, language: lang)
                        }
                        if self.settings.autoPaste, AutoPaster.paste() == .pasted { pasted = true }
                    }
                    // A newer dictation may already own the UI — don't clobber it.
                    if self.state == .transcribing, gen == self.dictationGeneration {
                        self.overlay.show(.done(text, pasted: pasted), autoHideAfter: text.isEmpty ? 1.2 : 1.0)
                        self.state = .ready
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if self.state == .transcribing, gen == self.dictationGeneration {
                        self.overlay.show(.error("Transcription error"), autoHideAfter: 2)
                        self.state = .ready
                    }
                }
            }
        }
    }

    private func abortRecordingIfNeeded() {
        pendingStop?.cancel(); pendingStop = nil
        if recorder.recording { _ = recorder.stop() }
        if state == .recording { overlay.hide() }
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
            menu.addItem(item("Allow “Input Monitoring”…", #selector(promptInputMonitoringMenu)))
            menu.addItem(.separator())
        }

        // Language submenu
        let langItem = NSMenuItem(title: "Language: \(settings.language.displayName)", action: nil, keyEquivalent: "")
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
        let modelItem = NSMenuItem(title: "Model: \(settings.model.shortLabel)", action: nil, keyEquivalent: "")
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
        let keyItem = NSMenuItem(title: "Key: \(settings.pttKey.displayName)", action: nil, keyEquivalent: "")
        let keyMenu = NSMenu()
        for k in PushToTalk.Key.allCases {
            let mi = item(k.displayName, #selector(selectKey(_:)))
            mi.representedObject = k.rawValue
            mi.state = (k == settings.pttKey) ? .on : .off
            keyMenu.addItem(mi)
        }
        keyItem.submenu = keyMenu
        menu.addItem(keyItem)

        let sounds = item("Feedback Sounds", #selector(toggleSounds))
        sounds.state = settings.playSounds ? .on : .off
        menu.addItem(sounds)

        menu.addItem(.separator())
        menu.addItem(item("Open Söyle (history, settings)…", #selector(openSettings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(item("About Söyle", #selector(about)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Söyle", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func statusLine() -> String {
        switch state {
        case .loadingModel(let pct):
            // The downloader only reports per-file completion (verified: the big
            // weights file lands at once), so a percent is usually stuck at 0 —
            // show it only if it ever moves.
            guard let pct else { return "⏳ Loading model…" }
            return pct > 0 ? "⏳ Downloading model… \(pct)%"
                           : "⏳ Downloading model (\(settings.model.approxSize), one-time)…"
        case .ready: return "● Ready — hold \(settings.pttKey.displayName)"
        case .recording: return "🎙 Recording…"
        case .transcribing: return "✍️ Transcribing…"
        case .needsInputMonitoring: return "⚠️ Permission required"
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

    @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }

    @objc private func promptInputMonitoringMenu() { openSettings() }

    private func promptInputMonitoring() { openSettings() }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Söyle"
        alert.informativeText = "On-device voice dictation (NVIDIA Nemotron 3.5 ASR via MLX).\nHold \(settings.pttKey.displayName), speak, release — the text is pasted at your cursor and copied."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

private func AVCaptureDeviceStatusIsUndetermined() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
}
