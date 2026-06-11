import AppKit
import SoyleKit

/// Gate for the vocabulary's fuzzy layer: a real word of the user's language
/// must NEVER be auto-"corrected" toward a dictionary phrase ("Talking" stays
/// "Talking" unless explicitly listed as a variant). Backed by the system
/// spell checker. Main-thread only (NSSpellChecker requirement).
enum SpellCheck {
    static func isKnownWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        let setting = SettingsStore.shared.language
        // Check the dictation language plus English (tech vocabulary leaks
        // into every language); on auto, let the checker decide.
        let languages: [String] = setting == .auto
            ? []
            : [String(setting.rawValue.prefix(2)), "en"]
        if languages.isEmpty {
            return checker.checkSpelling(of: word, startingAt: 0).location == NSNotFound
        }
        for language in languages {
            let range = checker.checkSpelling(
                of: word, startingAt: 0, language: language,
                wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            if range.location == NSNotFound { return true }
        }
        return false
    }
}
