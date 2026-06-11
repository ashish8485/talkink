import XCTest
import CoreGraphics
@testable import Soyle
@testable import SoyleKit

// MARK: - App language list ↔ engine mappings

final class LanguageCoverageTests: XCTestCase {
    func testEveryAppLanguageReachesEveryEngineCorrectly() {
        for language in SoyleLanguage.allCases where language != .auto {
            let code = language.rawValue
            // Qwen3: the English-name table must cover the whole app list —
            // a hole would silently downgrade that language to auto-detect.
            XCTAssertNotNil(TranscriptionEngine.engineLanguage(code, for: .qwen3),
                            "\(code) missing from the Qwen3 name table")
            // Nemotron: BCP-47 passthrough except the Arabic special case.
            let nemotron = TranscriptionEngine.engineLanguage(code, for: .nemotron)
            XCTAssertEqual(nemotron, language == .arSA ? "ar" : code)
            // Voxtral ignores the parameter by design.
            XCTAssertNil(TranscriptionEngine.engineLanguage(code, for: .voxtral))
        }
    }

    func testAutoMeansNilEngineCode() {
        XCTAssertNil(SoyleLanguage.auto.engineCode)
        XCTAssertEqual(SoyleLanguage.frFR.engineCode, "fr-FR")
    }

    func testEveryLanguageHasDisplayNameAndFlag() {
        for language in SoyleLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty)
            XCTAssertFalse(language.flag.isEmpty)
        }
    }
}

// MARK: - Push-to-talk key interpretation

final class PushToTalkInterpretTests: XCTestCase {
    private let rightOption = PushToTalk.Key.rightOption
    private let alternate = CGEventFlags.maskAlternate.rawValue
    private let deviceRightAlt: UInt64 = 0x0000_0040
    private let deviceLeftAlt: UInt64 = 0x0000_0020

    private func flags(_ raw: UInt64) -> CGEventFlags { CGEventFlags(rawValue: raw) }

    func testIrrelevantKeyCodeIsIgnored() {
        XCTAssertNil(PushToTalk.interpret(type: .flagsChanged, keyCode: 58,
                                          flags: flags(alternate), autorepeat: false, key: rightOption))
    }

    func testRightOptionPressViaDeviceBit() {
        XCTAssertEqual(PushToTalk.interpret(type: .flagsChanged, keyCode: rightOption.rawValue,
                                            flags: flags(alternate | deviceRightAlt),
                                            autorepeat: false, key: rightOption), true)
    }

    func testRightOptionReleaseWhileLeftStillHeld() {
        // Releasing Right Option with Left Option still down keeps the generic
        // bit set — only the device bits reveal the release.
        XCTAssertEqual(PushToTalk.interpret(type: .flagsChanged, keyCode: rightOption.rawValue,
                                            flags: flags(alternate | deviceLeftAlt),
                                            autorepeat: false, key: rightOption), false)
    }

    func testRemapperWithoutDeviceBitsTrustsGenericFlag() {
        XCTAssertEqual(PushToTalk.interpret(type: .flagsChanged, keyCode: rightOption.rawValue,
                                            flags: flags(alternate),
                                            autorepeat: false, key: rightOption), true)
    }

    func testPlainReleaseClearsGenericFlag() {
        XCTAssertEqual(PushToTalk.interpret(type: .flagsChanged, keyCode: rightOption.rawValue,
                                            flags: flags(0), autorepeat: false, key: rightOption), false)
    }

    func testKeyDownAutorepeatIsIgnored() {
        XCTAssertNil(PushToTalk.interpret(type: .keyDown, keyCode: rightOption.rawValue,
                                          flags: flags(0), autorepeat: true, key: rightOption))
        XCTAssertEqual(PushToTalk.interpret(type: .keyDown, keyCode: rightOption.rawValue,
                                            flags: flags(0), autorepeat: false, key: rightOption), true)
    }

    func testKeyUpReleases() {
        XCTAssertEqual(PushToTalk.interpret(type: .keyUp, keyCode: rightOption.rawValue,
                                            flags: flags(0), autorepeat: false, key: rightOption), false)
    }
}

// MARK: - Hands-free double-tap machine

final class TapMachineTests: XCTestCase {
    func testPlainHoldAndRelease() {
        var m = PushToTalk.TapMachine()
        XCTAssertEqual(m.press(at: 0), .start)
        XCTAssertEqual(m.release(at: 1.2), .stop)
        XCTAssertFalse(m.locked)
    }

    func testDoubleTapLocksThenSingleTapStops() {
        var m = PushToTalk.TapMachine()
        XCTAssertEqual(m.press(at: 0), .start)        // tap 1 down
        XCTAssertEqual(m.release(at: 0.15), .stop)    // tap 1 up (aborted mini-dictation)
        XCTAssertEqual(m.press(at: 0.3), .start)      // tap 2 down → locks
        XCTAssertTrue(m.locked)
        XCTAssertEqual(m.release(at: 0.45), .none)    // up while locked: keep recording
        XCTAssertTrue(m.locked)
        XCTAssertEqual(m.press(at: 5.0), .stop)       // stop tap
        XCTAssertFalse(m.locked)
        XCTAssertEqual(m.release(at: 5.1), .none)     // its release is swallowed
        XCTAssertEqual(m.press(at: 9.0), .start)      // normal PTT resumes
        XCTAssertEqual(m.release(at: 10.0), .stop)
    }

    func testSlowSecondPressDoesNotLock() {
        var m = PushToTalk.TapMachine()
        _ = m.press(at: 0); _ = m.release(at: 0.15)
        XCTAssertEqual(m.press(at: 1.0), .start)      // 0.85s later: just a new dictation
        XCTAssertFalse(m.locked)
    }

    func testLongFirstHoldDoesNotLock() {
        var m = PushToTalk.TapMachine()
        _ = m.press(at: 0); _ = m.release(at: 2.0)    // a real dictation, not a tap
        XCTAssertEqual(m.press(at: 2.2), .start)
        XCTAssertFalse(m.locked, "re-pressing quickly after a long dictation must not lock")
    }

    func testDisabledSettingNeverLocks() {
        var m = PushToTalk.TapMachine()
        m.handsFreeEnabled = false
        _ = m.press(at: 0); _ = m.release(at: 0.15)
        _ = m.press(at: 0.3)
        XCTAssertFalse(m.locked)
    }

    func testVeryFirstPressNeverLocks() {
        var m = PushToTalk.TapMachine()
        XCTAssertEqual(m.press(at: 0.1), .start)
        XCTAssertFalse(m.locked)
    }

    func testResetClearsLockAndHistory() {
        var m = PushToTalk.TapMachine()
        _ = m.press(at: 0); _ = m.release(at: 0.15); _ = m.press(at: 0.3)
        XCTAssertTrue(m.locked)
        m.reset()
        XCTAssertFalse(m.locked)
        XCTAssertEqual(m.press(at: 0.4), .start)
        XCTAssertFalse(m.locked, "post-reset press must not see pre-reset taps")
    }

    func testForceLockActsLikeADoubleTap() {
        var m = PushToTalk.TapMachine()
        m.forceLock()                                  // talkink://record
        XCTAssertTrue(m.locked)
        XCTAssertEqual(m.press(at: 5.0), .stop)        // single tap ends it
        XCTAssertEqual(m.release(at: 5.1), .none)      // its release is swallowed
        XCTAssertEqual(m.press(at: 9.0), .start)       // normal PTT afterwards
    }
}

// MARK: - History stats

final class HistoryStatsTests: XCTestCase {
    func testWordsAndWPM() {
        let items = [
            HistoryItem(text: "one two three four five six", language: nil, audioSeconds: 20),
            HistoryItem(text: "seven eight nine ten", language: nil, audioSeconds: 20),
            HistoryItem(text: "untimed legacy entry", language: nil),   // old history: no duration
        ]
        let stats = HistoryStore.stats(of: items)
        XCTAssertEqual(stats.words, 13)
        XCTAssertEqual(stats.spokenSeconds, 40)
        // 10 timed words over 40s → 15 wpm
        XCTAssertEqual(stats.wordsPerMinute, 15)
    }

    func testWPMNeedsEnoughTimedMaterial() {
        let items = [HistoryItem(text: "hello world", language: nil, audioSeconds: 5)]
        XCTAssertNil(HistoryStore.stats(of: items).wordsPerMinute,
                     "5s of audio is not enough to claim a words-per-minute")
        XCTAssertEqual(HistoryStore.stats(of: []).words, 0)
    }
}

// MARK: - History persistence

final class HistoryStoreTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("soyle-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Tests must never write into the user's real error journal.
    private func makeStore(_ dir: URL) -> HistoryStore {
        HistoryStore(directory: dir,
                     errorLog: ErrorLog(fileURL: dir.appendingPathComponent("test-errors.json")))
    }

    func testAddPersistsAcrossReload() throws {
        let dir = try makeTempDir()
        let store = makeStore(dir)
        store.add(text: "  hello world  ", language: "en-US")
        XCTAssertEqual(store.items.first?.text, "hello world", "text is trimmed")

        let reloaded = makeStore(dir)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items.first?.text, "hello world")
        XCTAssertNil(reloaded.lastError)
    }

    func testEmptyTextIsIgnored() throws {
        let store = makeStore(try makeTempDir())
        store.add(text: "   \n ", language: nil)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testCapAtFiveHundred() throws {
        let store = makeStore(try makeTempDir())
        for i in 1...510 { store.add(text: "item \(i)", language: nil) }
        XCTAssertEqual(store.items.count, 500)
        XCTAssertEqual(store.items.first?.text, "item 510", "newest first")
    }

    func testCorruptFileIsPreservedNotDestroyed() throws {
        let dir = try makeTempDir()
        try Data("this is not json".utf8).write(to: dir.appendingPathComponent("history.json"))

        let store = makeStore(dir)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNotNil(store.lastError, "the user must learn their history couldn't be read")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("history.corrupt-") }
        XCTAssertEqual(backups.count, 1, "the damaged file must be parked, not overwritten")
    }

    func testDeleteAndClear() throws {
        let store = makeStore(try makeTempDir())
        store.add(text: "one", language: nil)
        store.add(text: "two", language: nil)
        store.delete(store.items[0])
        XCTAssertEqual(store.items.map(\.text), ["one"])
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }
}

// MARK: - Download failure wording

@MainActor
final class DownloadHumanMessageTests: XCTestCase {
    func testOfflineIsNamed() {
        let message = ModelDownloadCenter.humanMessage(for: URLError(.notConnectedToInternet))
        XCTAssertTrue(message.contains("offline"), message)
    }

    func testRateLimitIsNamed() {
        let message = ModelDownloadCenter.humanMessage(for: ModelDownloader.DownloadError.badStatus(429, "x"))
        XCTAssertTrue(message.contains("rate-limit"), message)
    }

    func testServerTroubleIsNamed() {
        let message = ModelDownloadCenter.humanMessage(for: ModelDownloader.DownloadError.badStatus(503, "x"))
        XCTAssertTrue(message.contains("503"), message)
    }

    func testDiskFullIsNamed() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let message = ModelDownloadCenter.humanMessage(for: error)
        XCTAssertTrue(message.lowercased().contains("disk"), message)
    }
}

// MARK: - Problem report

final class DiagnosticsReportTests: XCTestCase {
    func testGitHubURLTargetsTheRepoWithPrefilledBody() throws {
        let url = try XCTUnwrap(DiagnosticsReport.gitHubIssueURL(report: "MARKER-12345"))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertTrue(url.path.hasSuffix("/talkink/issues/new"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["labels"], "bug")
        XCTAssertNotNil(query["title"])
        XCTAssertTrue(try XCTUnwrap(query["body"]).contains("MARKER-12345"))
    }

    func testBodyIsCappedForURLLimits() throws {
        let huge = String(repeating: "x", count: 50_000)
        let url = try XCTUnwrap(DiagnosticsReport.gitHubIssueURL(report: huge))
        XCTAssertLessThan(url.absoluteString.count, 8_000, "URL must stay under browser/GitHub limits")
    }
}
