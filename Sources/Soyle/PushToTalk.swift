import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Global push-to-talk via a listen-only CGEventTap (needs Input Monitoring,
/// sandbox-friendly — Apple DTS's recommended approach). Detects hold/release of
/// a configurable key, including modifier keys (which only emit flagsChanged).
final class PushToTalk {
    /// Known good default keys. Modifier keys report press/release via flagsChanged.
    enum Key: Int, CaseIterable {
        case rightOption = 61   // kVK_RightOption (default)
        case leftOption  = 58   // kVK_Option
        case rightControl = 62  // kVK_RightControl
        case fn = 63            // kVK_Function (Globe) — needs "Press 🌐 = Do Nothing"

        var isModifier: Bool { true } // all current choices are modifiers

        /// The CGEventFlags bit whose presence means "pressed".
        var flagMask: CGEventFlags {
            switch self {
            case .rightOption, .leftOption: return .maskAlternate
            case .rightControl: return .maskControl
            case .fn: return .maskSecondaryFn
            }
        }

        /// NX_DEVICE*KEYMASK bits (IOKit/hidsystem/IOLLEvent.h) — the only way to
        /// tell the left and right instance of a modifier apart when BOTH are
        /// held (the generic mask stays set while either one is down).
        var deviceMask: UInt64? {
            switch self {
            case .leftOption:   return 0x0000_0020 // NX_DEVICELALTKEYMASK
            case .rightOption:  return 0x0000_0040 // NX_DEVICERALTKEYMASK
            case .rightControl: return 0x0000_2000 // NX_DEVICERCTLKEYMASK
            case .fn:           return nil         // no left/right variant
            }
        }

        /// Both device bits (left | right) of this key's modifier class.
        var deviceClassMask: UInt64 {
            switch self {
            case .leftOption, .rightOption: return 0x0000_0060
            case .rightControl:             return 0x0000_2001
            case .fn:                       return 0
            }
        }

        var displayName: String {
            switch self {
            case .rightOption: return "Right Option ⌥"
            case .leftOption: return "Left Option ⌥"
            case .rightControl: return "Right Control ⌃"
            case .fn: return "Fn / 🌐"
            }
        }
    }

    var onStart: () -> Void = {}
    var onStop: () -> Void = {}

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var key: Key
    private var isDown = false

    init(key: Key = .rightOption) {
        self.key = key
    }

    var isRunning: Bool { tap != nil }

    func setKey(_ newKey: Key) {
        guard newKey != key else { return }
        key = newKey
        isDown = false
    }

    /// Start the tap. Returns false if Input Monitoring isn't granted (tap can't be created).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Permissions.hasInputMonitoring else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<PushToTalk>.fromOpaque(refcon).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            }
        }
        tap = nil
        runLoopSource = nil
        if isDown { isDown = false; onStop() }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The OS can disable the tap if our callback is slow or on user input;
        // re-arm it so PTT keeps working for the whole session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let down = Self.interpret(type: type, keyCode: keyCode, flags: event.flags,
                                     autorepeat: autorepeat, key: key) {
            setDown(down)
        }
    }

    /// Pure press/release decision for `key`, nil if the event is irrelevant.
    /// Static and side-effect-free so it can be exercised by tests.
    static func interpret(type: CGEventType, keyCode: Int, flags: CGEventFlags,
                          autorepeat: Bool, key: Key) -> Bool? {
        guard keyCode == key.rawValue else { return nil }
        switch type {
        case .flagsChanged:
            // For a modifier, the generic flag present = pressed… except when the
            // OTHER side of the same modifier is also held (releasing ours keeps
            // the generic bit set). The device (L/R) bits disambiguate; trust
            // them only when present — remappers may strip them.
            let generic = flags.contains(key.flagMask)
            if generic, let dev = key.deviceMask, flags.rawValue & key.deviceClassMask != 0 {
                return flags.rawValue & dev != 0
            }
            return generic
        case .keyDown:
            // Plain (non-modifier) key path; ignore auto-repeat.
            return autorepeat ? nil : true
        case .keyUp:
            return false
        default:
            return nil
        }
    }

    private func setDown(_ down: Bool) {
        guard down != isDown else { return }
        isDown = down
        // Dispatch to main so UI/audio work never blocks the tap callback.
        DispatchQueue.main.async { [weak self] in
            down ? self?.onStart() : self?.onStop()
        }
    }
}
