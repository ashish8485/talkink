import AppKit

// Headless self-test path (no GUI). Verifies bundled metallib + model + transcription.
if let i = CommandLine.arguments.firstIndex(of: "--selftest") {
    let path = (i + 1 < CommandLine.arguments.count) ? CommandLine.arguments[i + 1] : ""
    SelfTest.run(audioPath: path) // never returns
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
