import Foundation
import AppKit
import Carbon
import LidSensorKit

public struct HotkeyCombination: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public static let defaultHotkey = HotkeyCombination(
        keyCode: 1, // 'S' key (kVK_ANSI_S)
        carbonModifiers: UInt32(cmdKey | optionKey) // ⌥⌘S (2048 | 256 = 2304)
    )

    public static let controlOptionCommandS = HotkeyCombination(
        keyCode: 1,
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    public static let shiftCommandS = HotkeyCombination(
        keyCode: 1,
        carbonModifiers: UInt32(shiftKey | cmdKey)
    )

    public var displayString: String {
        var str = ""
        if carbonModifiers & UInt32(controlKey) != 0 { str += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { str += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { str += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { str += "⌘" }
        str += keyGlyph(for: keyCode)
        return str
    }

    public var keyEquivalent: String {
        return keyGlyph(for: keyCode).lowercased()
    }

    public var modifierMask: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    public static func from(event: NSEvent) -> HotkeyCombination? {
        let carbonFlags = carbonModifierFlags(from: event.modifierFlags)
        guard carbonFlags != 0 else { return nil }
        return HotkeyCombination(keyCode: UInt32(event.keyCode), carbonModifiers: carbonFlags)
    }

    public static func carbonModifierFlags(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if cocoaFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    private func keyGlyph(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return "Key\(keyCode)"
        }
    }
}

@MainActor
public final class GlobalHotkeyManager: ObservableObject {
    public static let shared = GlobalHotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeySignature: OSType = 0x4D434847 // 'MCHG' (MacHinge)
    private let hotKeyID: UInt32 = 1

    public var onCalibrateTriggered: (@MainActor () -> Void)?

    private init() {
        installCarbonEventHandler()
    }

    public func setup() {
        registerCurrentHotkey()
    }

    public func registerCurrentHotkey() {
        unregisterHotkey()

        let settings = AppSettings.shared
        guard settings.isHotkeyEnabled else { return }

        let combo = settings.hotkeyCombination
        let hotKeyIDStruct = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyIDStruct,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            NSLog("[GlobalHotkeyManager] Registered global hotkey: %@", combo.displayString)
        } else {
            NSLog("[GlobalHotkeyManager] Failed to register global hotkey (status: %d)", status)
        }
    }

    public func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            guard let event = event else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr && hotKeyID.signature == 0x4D434847 && hotKeyID.id == 1 {
                Task { @MainActor in
                    GlobalHotkeyManager.shared.handleHotkeyTriggered()
                }
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    public func handleHotkeyTriggered() {
        NSLog("[GlobalHotkeyManager] Hotkey triggered by user")
        if let onCalibrate = onCalibrateTriggered {
            onCalibrate()
        } else {
            if let live = LidAngleSensor.shared.readCurrentAngle() {
                AppSettings.shared.setCustomAngleFromCurrentSensor(live.angle)
                CalibrationToastHUD.shared.show(angle: live.angle)
            } else {
                let saved = AppSettings.shared.effectivePreferredAngle
                CalibrationToastHUD.shared.show(angle: saved)
            }
        }
    }
}
