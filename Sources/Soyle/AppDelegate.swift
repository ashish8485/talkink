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
        case loadFailed(String)             // model load/download failed — reason stays visible in the menu
    }

    private let settings = SettingsStore.shared
    private let engine = TranscriptionEngine(model: SettingsStore.shared.modelOption)
    private let ptt = PushToTalk(key: SettingsStore.shared.pttKey)
    private let recorder = Recorder()
    private let overlay = OverlayController()
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)

    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var armTimer: Timer?
    private var modelLoadFailed = false          // retry trigger (display lives in .loadFailed)
    private var lastLoadFailureReason: String?
    private var updateAvailableVersion: String?  // set by Sparkle → prominent menu item
    private var languageRescues = 0              // empty transcripts rescued by auto-detect
    private var loadTask: Task<Void, Never>?     // the one tracked selected-model load
    private var pendingStop: DispatchWorkItem?   // release-grace timer (tail capture)
    private var dictationGeneration = 0          // ignore stale transcription completions
    private var recordingStartedAt: Date?        // wall clock, to spot dead-capture sessions
    private var transcriptionWatchdog: DispatchWorkItem?
    private var state: AppState = .loadingModel(progress: nil) { didSet { updateMenu(); updateStatusIcon() } }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CrashSentinel.checkAndArm()
        setupStatusItem()

        recorder.onLevel = { [weak self] lvl in self?.overlay.updateLevel(lvl) }
        recorder.onFailure = { [weak self] reason in
            DispatchQueue.main.async { self?.recordingBroke(reason) }
        }
        ptt.onStart = { [weak self] in self?.startRecording() }
        ptt.onStop = { [weak self] in self?.stopRecording() }
        ptt.onTapDisabled = { [weak self] in self?.tapDied() }
        // Menu-bar % follows the SELECTED model's download in the center
        // (downloads of other models run concurrently and don't touch it).
        ModelDownloadCenter.shared.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                guard let self else { return }
                if case .downloading(let fraction) = states[self.settings.modelID] {
                    let pct = min(99, Int(fraction * 100))
                    if case .loadingModel(let current) = self.state, current != pct {
                        self.state = .loadingModel(progress: pct)
                    }
                }
            }
            .store(in: &cancellables)

        ptt.handsFreeEnabled = settings.handsFreeDoubleTap
        observeSettings()
        requestPermissionsThenStart()
        loadModel()

        Updater.shared.automaticallyChecksForUpdates = settings.checkForUpdates
        settings.$checkForUpdates
            .dropFirst()
            .sink { Updater.shared.automaticallyChecksForUpdates = $0 }
            .store(in: &cancellables)
        // An available update should never hide behind "Check for Updates…" —
        // Sparkle's own alert pops, and the menu gets a prominent install item.
        Updater.shared.onUpdateAvailable = { [weak self] version in
            self?.updateAvailableVersion = version
            self?.updateMenu()
        }

        announceVersionChangeIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CrashSentinel.disarm()
        ptt.stop()
        pendingStop?.cancel()
        _ = recorder.stop()
        armTimer?.invalidate()
    }

    /// First launch of a new version: open the window so the user SEES the
    /// update landed (menu-bar apps otherwise update invisibly) — and a failed
    /// post-update relaunch self-heals into a visible confirmation when the
    /// user relaunches manually.
    private func announceVersionChangeIfNeeded() {
        let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        let key = "soyle.lastLaunchedVersion"
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(current, forKey: key)
        guard let previous, previous != current else { return }
        Log.app.notice("updated \(previous, privacy: .public) → \(current, privacy: .public)")
        settings.justUpdatedToVersion = current
        DispatchQueue.main.async { [weak self] in self?.openSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        tryRearm()
        // Recover a failed model load (e.g. offline at first run) without a relaunch.
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
            if engine.isLoaded {
                state = .ready
            } else if modelLoadFailed {
                state = .loadFailed(lastLoadFailureReason ?? "Model not loaded — it retries when you dictate")
            } else {
                state = .loadingModel(progress: nil)
            }
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
        startModelLoad(of: settings.modelOption)
    }

    /// One tracked load at a time: selecting another model cancels the wait on
    /// the previous one (its download keeps running concurrently in the
    /// center — resumable, never wasted) and the stale task can no longer
    /// touch UI state thanks to the post-await cancellation guards.
    private func startModelLoad(of target: ASRModelOption) {
        loadTask?.cancel()
        modelLoadFailed = false
        // Pre-flight: refuse a load that can't fit in unified memory — letting
        // MLX try anyway can abort the whole process (Metal allocation failure),
        // which to the user is "the app vanished".
        switch SystemResources.memoryVerdict(forWeightsGB: target.sizeGB) {
        case .insufficient(let message):
            registerLoadFailure(reason: message, target: target)
            overlay.show(.error(message), autoHideAfter: 5)
            return
        case .tight(let message):
            ErrorLog.shared.record(component: "model", message: "\(target.displayName): \(message)")
            overlay.show(.error(message), autoHideAfter: 4)
        case .ok:
            break
        }
        // Never clobber the permission gate — it owns the menu until the tap
        // is armed (otherwise the re-arm timer's guard can never fire and the
        // app shows "Ready" with a dead hotkey).
        if state != .needsInputMonitoring { state = .loadingModel(progress: nil) }
        let center = ModelDownloadCenter.shared
        loadTask = Task { @MainActor in
            do {
                try await center.ensureDownloaded(target).value
                guard !Task.isCancelled else { return }
                center.markPreparing(target)
                try await engine.load()
                guard !Task.isCancelled else { center.clearLoadMarker(target); return }
                await Task.detached(priority: .userInitiated) { [engine] in engine.warmUp() }.value
                guard !Task.isCancelled else { center.clearLoadMarker(target); return }
                // A concurrent model switch may have invalidated this load — only
                // a load whose weights are actually installed flips to .ready.
                if engine.isLoaded {
                    center.markActive(target)
                    if state != .needsInputMonitoring { state = .ready } else { updateMenu() }
                } else {
                    center.clearLoadMarker(target)
                }
            } catch is CancellationError {
                center.clearLoadMarker(target)
            } catch {
                center.clearLoadMarker(target)
                let reason = Self.loadFailureMessage(for: error)
                registerLoadFailure(reason: reason, target: target, detail: String(describing: error))
                overlay.show(.error(reason), autoHideAfter: 4)
            }
        }
    }

    private func registerLoadFailure(reason: String, target: ASRModelOption, detail: String? = nil) {
        modelLoadFailed = true
        lastLoadFailureReason = reason
        ErrorLog.shared.record(component: "model",
                               message: "\(target.displayName) couldn't load — \(reason)",
                               detail: detail)
        if state != .needsInputMonitoring { state = .loadFailed(reason) }
    }

    /// Honest, actionable load-failure wording (offline vs disk vs generic).
    private static func loadFailureMessage(for error: Error) -> String {
        if let preflight = error as? PreflightError {
            return preflight.errorDescription ?? "Pre-flight check failed."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .dataNotAllowed, .cannotFindHost, .dnsLookupFailed:
                return "Can't download the model — you appear to be offline. It retries when you dictate."
            case .timedOut, .networkConnectionLost:
                return "The model download was interrupted — it resumes when you dictate."
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError {
            return "Not enough disk space to finish the model download."
        }
        return "The model couldn't load (\(ns.localizedDescription)). See Settings → Report a Problem."
    }

    private func observeSettings() {
        settings.$modelID
            .dropFirst()
            .sink { [weak self] id in
                guard let option = ASRCatalog.option(forID: id) else { return }
                self?.reloadModel(option)
            }
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
        // The user adjusted the language — restart the mismatch detector.
        settings.$language
            .dropFirst()
            .sink { [weak self] _ in self?.languageRescues = 0 }
            .store(in: &cancellables)
        settings.$handsFreeDoubleTap
            .dropFirst()
            .sink { [weak self] enabled in self?.ptt.handsFreeEnabled = enabled }
            .store(in: &cancellables)
    }

    private func reloadModel(_ newModel: ASRModelOption) {
        // Refuse a switch that can't fit in memory BEFORE dropping the current
        // weights: the user keeps a working model and learns why.
        if case .insufficient(let message) = SystemResources.memoryVerdict(forWeightsGB: newModel.sizeGB) {
            ErrorLog.shared.record(component: "model",
                                   message: "\(newModel.displayName) selection refused — \(message)")
            presentModelRefused(newModel, reason: message)
            if settings.modelID != engine.model.id {
                settings.modelID = engine.model.id   // snap the picker back to reality
            }
            return
        }
        // Leaving .recording without stopping the recorder would swallow the
        // PTT release in stopRecording's guard and leave the mic running.
        abortRecordingIfNeeded()
        engine.switchModel(to: newModel)
        startModelLoad(of: newModel)
    }

    private func presentModelRefused(_ model: ASRModelOption, reason: String) {
        let alert = NSAlert()
        alert.messageText = "\(model.displayName) won't fit in memory"
        alert.informativeText = reason
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
            } else if case .loadFailed = state {
                // "Retries when you dictate" — keep that promise right here.
                overlay.show(.error("Model not loaded — retrying now…"), autoHideAfter: 2)
                loadModel()
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
            recordingStartedAt = Date()
            state = .recording
            overlay.show(.recording(handsFree: ptt.isHandsFreeLocked))
            playSound(start: true)
        } catch {
            ErrorLog.shared.record(component: "audio",
                                   message: "Recording couldn't start",
                                   detail: error.localizedDescription)
            overlay.show(.error("Microphone unavailable — \(error.localizedDescription)"), autoHideAfter: 3)
        }
    }

    /// Mid-recording capture failure (device yanked and recovery failed):
    /// stop cleanly and say so — never keep "recording" silence.
    private func recordingBroke(_ reason: String) {
        ErrorLog.shared.record(component: "audio", message: "Recording aborted — \(reason)")
        guard state == .recording else { return }
        abortRecordingIfNeeded()
        state = .ready
        overlay.show(.error("Microphone lost — dictation stopped"), autoHideAfter: 3)
    }

    /// The event tap died and PushToTalk's re-enable didn't stick: recreate it,
    /// or fall back to the permission gate — never a silently dead hotkey.
    private func tapDied() {
        ErrorLog.shared.record(component: "hotkey",
                               message: "Push-to-talk tap disabled by the system and re-enable failed")
        ptt.stop()
        if Permissions.hasInputMonitoring, ptt.start() {
            Log.app.notice("event tap recreated after system disable")
            return
        }
        state = .needsInputMonitoring
        startArmTimer()
        overlay.show(.error("Push-to-talk lost — check Input Monitoring"), autoHideAfter: 4)
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
        let wallClock = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil

        // Ignore accidental taps (< 0.25s of speech + the 0.25s tail) — but a
        // LONG hold that produced (near) nothing is a broken capture, not a
        // tap: the user spoke into a dead pipeline and must know.
        guard samples.count >= 8_000 else {
            if wallClock >= 1.5 {
                ErrorLog.shared.record(component: "audio", message: String(
                    format: "Held the key %.1fs but captured only %d samples — the input device produced no audio",
                    wallClock, samples.count))
                overlay.show(.error("No audio captured — check your input device (System Settings → Sound)"),
                             autoHideAfter: 4)
            } else {
                overlay.hide()
            }
            if state == .transcribing { state = .ready }
            return
        }

        dictationGeneration += 1
        let gen = dictationGeneration
        let lang = settings.language.engineCode

        // Watchdog: an inference that hangs (Metal stall, library bug) must not
        // leave "Transcribing…" on screen forever with the hotkey locked out.
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.state == .transcribing, gen == self.dictationGeneration else { return }
            ErrorLog.shared.record(component: "model",
                                   message: "Transcription still running after 120s — state reset so dictation keeps working")
            self.state = .ready
            self.overlay.show(.error("Transcription stalled — please try again (and Report a Problem)"),
                              autoHideAfter: 5)
        }
        transcriptionWatchdog?.cancel()
        transcriptionWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: watchdog)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                var result = try self.engine.transcribe(samples: samples, language: lang)
                // A model conditioned on the wrong language can return an
                // EMPTY transcript for perfectly good speech (verified:
                // Nemotron + sv-SE prompt on French audio → empty). One
                // silent retry in auto-detect rescues the dictation.
                if result.text.isEmpty, lang != nil {
                    let rescue = try self.engine.transcribe(samples: samples, language: nil)
                    if !rescue.text.isEmpty {
                        result = rescue
                        DispatchQueue.main.async { self.noteLanguageRescue() }
                    }
                }
                let text = result.text
                DispatchQueue.main.async {
                    self.transcriptionWatchdog?.cancel()
                    self.deliver(text: text, samples: samples, forcedLanguage: lang, generation: gen)
                }
            } catch {
                DispatchQueue.main.async {
                    self.transcriptionWatchdog?.cancel()
                    ErrorLog.shared.record(component: "model",
                                           message: "Transcription failed",
                                           detail: error.localizedDescription)
                    if self.state == .transcribing, gen == self.dictationGeneration {
                        self.overlay.show(.error("Transcription error — \(error.localizedDescription)"),
                                          autoHideAfter: 3)
                        self.state = .ready
                    }
                }
            }
        }
    }

    /// Hand the transcript to the user, with an honest account of what
    /// happened: empty results are explained (silence vs unrecognized speech
    /// vs language mismatch), clipboard writes are verified, and a skipped
    /// auto-paste always says why.
    private func deliver(text rawText: String, samples: [Float], forcedLanguage lang: String?, generation gen: Int) {
        // The user's vocabulary fixes names/jargon first, so History, the
        // clipboard and the paste all carry the corrected form. The spell-check
        // gate keeps the fuzzy layer away from real words (main-thread only).
        let text = Vocabulary.shared.apply(to: rawText, isKnownWord: SpellCheck.isKnownWord)
        let isCurrent = (state == .transcribing && gen == dictationGeneration)
        let outcome: DictationOutcome

        if text.isEmpty {
            let stats = SpeechStats.analyze(samples: samples)
            if !stats.likelySpeech {
                outcome = .noSpeech
            } else if lang != nil {
                // Auto-detect rescue already ran and stayed empty too.
                outcome = .wrongLanguage(settings.language.displayName)
                ErrorLog.shared.record(component: "model", message: String(
                    format: "Speech detected (%.1fs active, peak %.3f) but empty transcript with language %@ — auto rescue empty too",
                    stats.activeSeconds, stats.peakRMS, settings.language.displayName))
            } else {
                outcome = .notRecognized
                ErrorLog.shared.record(component: "model", message: String(
                    format: "Speech detected (%.1fs active) but the model returned an empty transcript (language: auto)",
                    stats.activeSeconds))
            }
        } else {
            if !AutoPaster.secureInputActive {
                // Words are never lost, even when a newer dictation owns the UI.
                HistoryStore.shared.add(text: text, language: lang)
            }
            guard isCurrent else { return }   // stale: archived above, hands off the clipboard
            guard Clipboard.copy(text) else {
                // No ⌘V either — synthesizing it would paste the clipboard's
                // PREVIOUS content into the user's document.
                ErrorLog.shared.record(component: "paste",
                                       message: "Clipboard write failed — transcript NOT copied (it is in History)")
                overlay.show(.error("Couldn't copy — recover the text from History"), autoHideAfter: 4)
                state = .ready
                return
            }
            if settings.autoPaste {
                switch AutoPaster.paste() {
                case .pasted:
                    outcome = .pasted
                case .noAccessibility:
                    outcome = .copiedNoAccessibility
                    ErrorLog.shared.record(component: "paste",
                                           message: "Auto-paste skipped — Accessibility not granted")
                case .secureField:
                    outcome = .copiedSecureField
                }
            } else {
                outcome = .copied
            }
        }

        if isCurrent {
            overlay.show(.done(text, outcome: outcome), autoHideAfter: Self.hideDelay(for: outcome))
            state = .ready
        }
    }

    /// Successes vanish fast; anything the user should read lingers.
    private static func hideDelay(for outcome: DictationOutcome) -> Double {
        switch outcome {
        case .pasted, .copied: return 1.0
        case .noSpeech: return 1.6
        case .copiedSecureField: return 3.0
        case .copiedNoAccessibility, .notRecognized: return 3.5
        case .wrongLanguage: return 4.5
        }
    }

    /// Auto-detect had to rescue an empty transcript — the configured
    /// language doesn't match what's being spoken. After three rescues in a
    /// row, gently point at the setting (each rescue costs a second pass).
    private func noteLanguageRescue() {
        languageRescues += 1
        guard languageRescues == 3 else { return }
        let langName = settings.language.displayName
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.overlay.show(
                .error("Tip: language is set to \(langName) — Auto would fit your speech better (Settings → Language)."),
                autoHideAfter: 5)
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
        case .needsInputMonitoring, .loadFailed: symbol = "exclamationmark.triangle.fill"
        default: symbol = "mic"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Talkink")
        button.image?.isTemplate = (state != .recording)
        button.contentTintColor = (state == .recording) ? .nvidia : nil
    }

    private func updateMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        // An available update gets a first-class item — nobody should have to
        // think of clicking "Check for Updates…" to learn about it.
        if let version = updateAvailableVersion {
            menu.addItem(item("⬆️ Update to \(version) — Install…", #selector(checkForUpdates)))
            menu.addItem(.separator())
        }

        if state == .needsInputMonitoring {
            menu.addItem(item("Allow “Input Monitoring”…", #selector(promptInputMonitoringMenu)))
            menu.addItem(.separator())
        }
        if case .loadFailed = state {
            menu.addItem(item("Retry Loading the Model", #selector(retryModelLoad)))
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
        let modelItem = NSMenuItem(title: "Model: \(settings.modelOption.displayName)", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for option in ASRCatalog.options {
            let suffix = option == ASRCatalog.default ? " — recommended" : ""
            let mi = item("\(option.displayName)  (\(option.sizeLabel))\(suffix)", #selector(selectModel(_:)))
            mi.representedObject = option.id
            mi.state = (option.id == settings.modelID) ? .on : .off
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
        menu.addItem(item("Open Talkink (history, settings)…", #selector(openSettings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(item("Report a Problem…", #selector(reportProblem)))
        menu.addItem(item("About Talkink", #selector(about)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Talkink", #selector(quit), key: "q"))

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
                           : "⏳ Downloading model (\(settings.modelOption.sizeLabel), one-time)…"
        case .ready: return "● Ready — hold \(settings.pttKey.displayName)"
        case .recording:
            return ptt.isHandsFreeLocked
                ? "🎙 Recording — tap \(settings.pttKey.displayName) to stop"
                : "🎙 Recording…"
        case .transcribing: return "✍️ Transcribing…"
        case .needsInputMonitoring: return "⚠️ Permission required"
        case .loadFailed(let reason): return "⚠️ \(String(reason.prefix(72)))"
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
        if let id = sender.representedObject as? String, ASRCatalog.option(forID: id) != nil {
            settings.modelID = id
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

    /// Re-opening the app (double-click in Applications, `open`, Dock) while
    /// it's already running should surface the UI — standard macOS behaviour,
    /// and the only discoverable "where did it go?" recovery for a menu-bar app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openSettings() }
        return true
    }

    @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }

    @objc private func retryModelLoad() { loadModel() }

    @objc private func reportProblem() {
        settingsWindowController.show()
        NotificationCenter.default.post(name: .soyleOpenReport, object: nil)
    }

    @objc private func promptInputMonitoringMenu() { openSettings() }

    private func promptInputMonitoring() { openSettings() }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Talkink"
        alert.informativeText = "On-device voice dictation — \(settings.modelOption.displayName) via Apple MLX.\nHold \(settings.pttKey.displayName), speak, release — the text is pasted at your cursor and copied."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

private func AVCaptureDeviceStatusIsUndetermined() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
}
