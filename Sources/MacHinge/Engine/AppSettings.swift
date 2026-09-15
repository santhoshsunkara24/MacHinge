import Foundation
import Combine
import SwiftUI
import LidSensorKit

public enum TransitionCurve: String, CaseIterable, Identifiable, Codable {
    case smoothstep  = "Smoothstep (S-Curve)"
    case easeInOut   = "Ease-In-Out Sine"
    case power14     = "Natural Ease (Power 1.4)"
    case linear      = "Linear"

    public var id: String { rawValue }
}

public enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

public enum VisualEffectStyle: String, CaseIterable, Identifiable, Codable {
    case frostedGlass = "Duo Effect"
    case luminousGlow = "Luminous Wake & Fold Glow"
    case magneticLens = "Magnetic Lens Distortion"

    public var id: String { rawValue }
}

public enum ViewingAnglePreset: String, CaseIterable, Identifiable, Codable {
    case standard80     = "80° — Standard (Starts at 80°)"
    case upright90      = "90° — Upright"
    case balanced100    = "100° — Balanced"
    case comfortable105 = "105° — Comfortable"
    case moreOpen110    = "110° — More Open"
    case custom         = "Custom — Set My Own"

    public var id: String { rawValue }

    public var angleValue: Double? {
        switch self {
        case .standard80:     return 80.0
        case .upright90:      return 90.0
        case .balanced100:    return 100.0
        case .comfortable105: return 105.0
        case .moreOpen110:    return 110.0
        case .custom:         return nil
        }
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Keys
    private let kIsEnabled = "machinge.isEnabled"
    private let kPreset = "machinge.viewingAnglePreset"
    private let kCustomAngle = "machinge.customPreferredAngle"
    private let kClosingTriggerAngle = "machinge.closingTriggerAngle"
    private let kClosedEndpoint = "machinge.closedEndpointAngle"
    private let kDeadband = "machinge.deadbandDegrees"
    private let kIntensity = "machinge.animationIntensity"
    private let kCurve = "machinge.transitionCurve"
    private let kEffectStyle = "machinge.visualEffectStyle"
    private let kGlowIntensity = "machinge.glowIntensity"
    private let kLaunchAtLogin = "machinge.launchAtLogin"
    private let kShowDebug = "machinge.showDebugControls"
    private let kHasCompletedOnboarding = "machinge.hasCompletedOnboarding"
    private let kIsHotkeyEnabled = "machinge.isHotkeyEnabled"
    private let kHotkeyKeyCode = "machinge.hotkeyKeyCode"
    private let kHotkeyModifiers = "machinge.hotkeyModifiers"
    private let kAppAppearance = "machinge.appAppearance"

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: kIsEnabled) }
    }

    @Published public var appAppearance: AppAppearance {
        didSet {
            defaults.set(appAppearance.rawValue, forKey: kAppAppearance)
            updateSystemAppearance()
        }
    }

    public func updateSystemAppearance() {
        NSApp?.appearance = appAppearance.nsAppearance
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: kHasCompletedOnboarding) }
    }

    @Published public var isHotkeyEnabled: Bool {
        didSet {
            defaults.set(isHotkeyEnabled, forKey: kIsHotkeyEnabled)
            GlobalHotkeyManager.shared.registerCurrentHotkey()
        }
    }

    @Published public var hotkeyCombination: HotkeyCombination {
        didSet {
            defaults.set(hotkeyCombination.keyCode, forKey: kHotkeyKeyCode)
            defaults.set(hotkeyCombination.carbonModifiers, forKey: kHotkeyModifiers)
            GlobalHotkeyManager.shared.registerCurrentHotkey()
        }
    }

    @Published public var preset: ViewingAnglePreset {
        didSet { defaults.set(preset.rawValue, forKey: kPreset) }
    }

    @Published public var visualEffectStyle: VisualEffectStyle {
        didSet { defaults.set(visualEffectStyle.rawValue, forKey: kEffectStyle) }
    }

    @Published public var glowIntensity: Double {
        didSet { defaults.set(glowIntensity, forKey: kGlowIntensity) }
    }

    public static let defaultClosingTriggerAngle: Double = 78.0

    @Published public var customPreferredAngle: Double {
        didSet { defaults.set(customPreferredAngle, forKey: kCustomAngle) }
    }

    public var effectStartAngle: Double {
        return effectivePreferredAngle - 18.0
    }

    public var closingTriggerAngle: Double {
        return effectStartAngle
    }

    @Published public var closedEndpointAngle: Double {
        didSet { defaults.set(closedEndpointAngle, forKey: kClosedEndpoint) }
    }

    @Published public var deadbandDegrees: Double {
        didSet { defaults.set(deadbandDegrees, forKey: kDeadband) }
    }

    @Published public var animationIntensity: Double {
        didSet { defaults.set(animationIntensity, forKey: kIntensity) }
    }

    @Published public var transitionCurve: TransitionCurve {
        didSet { defaults.set(transitionCurve.rawValue, forKey: kCurve) }
    }

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: kLaunchAtLogin) }
    }

    @Published public var showDebugControls: Bool {
        didSet { defaults.set(showDebugControls, forKey: kShowDebug) }
    }

    public var effectivePreferredAngle: Double {
        if let presetValue = preset.angleValue {
            return presetValue
        }
        return customPreferredAngle
    }

    public init() {
        self.isEnabled = defaults.object(forKey: kIsEnabled) != nil ? defaults.bool(forKey: kIsEnabled) : true
        let savedAppearanceStr = defaults.string(forKey: kAppAppearance) ?? AppAppearance.system.rawValue
        self.appAppearance = AppAppearance(rawValue: savedAppearanceStr) ?? .system
        self.hasCompletedOnboarding = defaults.bool(forKey: kHasCompletedOnboarding)
        self.isHotkeyEnabled = defaults.object(forKey: kIsHotkeyEnabled) != nil ? defaults.bool(forKey: kIsHotkeyEnabled) : true

        let savedKeyCode = defaults.object(forKey: kHotkeyKeyCode) != nil ? UInt32(defaults.integer(forKey: kHotkeyKeyCode)) : HotkeyCombination.defaultHotkey.keyCode
        let savedModifiers = defaults.object(forKey: kHotkeyModifiers) != nil ? UInt32(defaults.integer(forKey: kHotkeyModifiers)) : HotkeyCombination.defaultHotkey.carbonModifiers
        self.hotkeyCombination = HotkeyCombination(keyCode: savedKeyCode, carbonModifiers: savedModifiers)
        
        let savedPresetStr = defaults.string(forKey: kPreset) ?? ViewingAnglePreset.standard80.rawValue
        self.preset = ViewingAnglePreset(rawValue: savedPresetStr) ?? .standard80

        if let savedCustom = defaults.object(forKey: kCustomAngle) as? Double {
            self.customPreferredAngle = savedCustom
        } else {
            self.customPreferredAngle = 80.0
        }

        let rawEndpoint = defaults.object(forKey: kClosedEndpoint) != nil ? defaults.double(forKey: kClosedEndpoint) : 25.0
        self.closedEndpointAngle = rawEndpoint
        self.deadbandDegrees = 0.0 // Starts exactly at 80.0°
        self.animationIntensity = defaults.object(forKey: kIntensity) != nil ? defaults.double(forKey: kIntensity) : 1.0

        let savedCurveStr = defaults.string(forKey: kCurve) ?? TransitionCurve.smoothstep.rawValue
        self.transitionCurve = TransitionCurve(rawValue: savedCurveStr) ?? .smoothstep

        let savedStyleStr = defaults.string(forKey: kEffectStyle) ?? VisualEffectStyle.luminousGlow.rawValue
        self.visualEffectStyle = VisualEffectStyle(rawValue: savedStyleStr) ?? .luminousGlow
        self.glowIntensity = defaults.object(forKey: kGlowIntensity) != nil ? defaults.double(forKey: kGlowIntensity) : 1.0

        self.launchAtLogin = defaults.bool(forKey: kLaunchAtLogin)
        self.showDebugControls = defaults.bool(forKey: kShowDebug)

        updateSystemAppearance()
    }

    public func setCustomAngleFromCurrentSensor(_ angle: Double) {
        self.customPreferredAngle = round(angle * 10.0) / 10.0
        self.preset = .custom
    }

    public func resetEffectSettings() {
        self.visualEffectStyle = .luminousGlow
        self.glowIntensity = 1.0
        self.animationIntensity = 1.0
        self.closedEndpointAngle = 25.0
        self.transitionCurve = .smoothstep
    }

    public func resetToDefaults() {
        self.isEnabled = true
        self.appAppearance = .system
        self.isHotkeyEnabled = true
        self.hotkeyCombination = .defaultHotkey
        self.preset = .standard80
        self.visualEffectStyle = .luminousGlow
        self.glowIntensity = 1.0
        self.customPreferredAngle = 80.0
        self.closedEndpointAngle = 25.0
        self.deadbandDegrees = 0.0
        self.animationIntensity = 1.0
        self.transitionCurve = .smoothstep
        self.showDebugControls = false
    }
}
