import Foundation
import Combine
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
        case .auto: return "Auto (détection)"
        case .frFR: return "Français"
        case .enUS: return "English"
        case .deDE: return "Deutsch"
        case .esES: return "Español"
        case .itIT: return "Italiano"
        case .ptPT: return "Português"
        case .trTR: return "Türkçe"
        case .arSA: return "العربية"
        case .nlNL: return "Nederlands"
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
        static let trimWhitespace = "soyle.trimWhitespace"
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

    private init() {
        language = SoyleLanguage(rawValue: defaults.string(forKey: K.language) ?? "") ?? .auto
        model = SoyleModel(rawValue: defaults.string(forKey: K.model) ?? "") ?? .int8
        let keyRaw = defaults.object(forKey: K.pttKey) as? Int
        pttKey = PushToTalk.Key(rawValue: keyRaw ?? PushToTalk.Key.rightOption.rawValue) ?? .rightOption
        playSounds = defaults.object(forKey: K.playSounds) as? Bool ?? true
    }
}
