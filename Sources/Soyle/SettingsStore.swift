import Foundation
import Combine
import ServiceManagement
import SoyleKit

/// Available transcription languages. `auto` lets Nemotron detect the language.
enum SoyleLanguage: String, CaseIterable, Identifiable {
    case auto, frFR = "fr-FR", enUS = "en-US", deDE = "de-DE", esES = "es-ES",
         itIT = "it-IT", ptPT = "pt-PT", trTR = "tr-TR", arSA = "ar-SA", nlNL = "nl-NL"

    var id: String { rawValue }

    /// nil means "auto" for the engine.
    var engineCode: String? { self == .auto ? nil : rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (detect)"
        case .frFR: return "French"
        case .enUS: return "English"
        case .deDE: return "German"
        case .esES: return "Spanish"
        case .itIT: return "Italian"
        case .ptPT: return "Portuguese"
        case .trTR: return "Turkish"
        case .arSA: return "Arabic"
        case .nlNL: return "Dutch"
        }
    }
}

/// User preferences, persisted in UserDefaults. Defaults are sane for everyone;
/// everything is overridable in Settings.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private enum K {
        static let language = "soyle.language"
        static let model = "soyle.model"
        static let pttKey = "soyle.pttKey"
        static let playSounds = "soyle.playSounds"
        static let autoPaste = "soyle.autoPaste"
        static let checkForUpdates = "soyle.checkForUpdates"
        static let hasOnboarded = "soyle.hasOnboarded"
    }

    @Published var language: SoyleLanguage {
        didSet { defaults.set(language.rawValue, forKey: K.language) }
    }
    @Published var model: SoyleModel {
        didSet { defaults.set(model.rawValue, forKey: K.model) }
    }
    @Published var pttKey: PushToTalk.Key {
        didSet { defaults.set(pttKey.rawValue, forKey: K.pttKey) }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: K.playSounds) }
    }
    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: K.autoPaste) }
    }
    @Published var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: K.checkForUpdates) }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLoginItem(launchAtLogin) }
    }
    @Published var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: K.hasOnboarded) }
    }

    private init() {
        language = SoyleLanguage(rawValue: defaults.string(forKey: K.language) ?? "") ?? .auto
        model = SoyleModel(rawValue: defaults.string(forKey: K.model) ?? "") ?? .int8
        let keyRaw = defaults.object(forKey: K.pttKey) as? Int
        pttKey = PushToTalk.Key(rawValue: keyRaw ?? PushToTalk.Key.rightOption.rawValue) ?? .rightOption
        playSounds = defaults.object(forKey: K.playSounds) as? Bool ?? true
        autoPaste = defaults.object(forKey: K.autoPaste) as? Bool ?? true
        checkForUpdates = defaults.object(forKey: K.checkForUpdates) as? Bool ?? true
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        hasOnboarded = defaults.bool(forKey: K.hasOnboarded)
    }

    private func applyLoginItem(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Söyle: login item update failed: \(error.localizedDescription)")
        }
    }
}
