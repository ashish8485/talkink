import AppKit

/// Writes transcribed text to the system clipboard, ready to paste anywhere (⌘V).
enum Clipboard {
    /// False = the transcript is NOT on the clipboard. Callers must surface
    /// that (and must not synthesize ⌘V — it would paste the clipboard's
    /// PREVIOUS content into the user's document).
    static func copy(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(text, forType: .string)
    }
}
