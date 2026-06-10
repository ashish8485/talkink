import AppKit

// Headless self-test path (no GUI). Verifies bundled metallib + model + transcription.
if let i = CommandLine.arguments.firstIndex(of: "--selftest") {
    let path = (i + 1 < CommandLine.arguments.count) ? CommandLine.arguments[i + 1] : ""
    SelfTest.run(audioPath: path) // never returns
}

// Headless mic capture check — verifies the capture pipeline (and, on hardened
// runtime builds, the audio-input entitlement) without the GUI.
if CommandLine.arguments.contains("--mictest") {
    SelfTest.runMicTest() // never returns
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
