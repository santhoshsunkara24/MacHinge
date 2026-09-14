import SwiftUI
import LidSensorKit

public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var controller: AnimationController

    @State private var hasScreenRecordingPermission: Bool = ScreenCaptureEngine.hasScreenCaptureAccess()
    @State private var showingCalibrationBanner: Bool = false
    @State private var savedAngleBannerValue: Double = 0.0
    @State private var isRecordingShortcut: Bool = false
    @State private var shortcutEventMonitor: Any?
    @State private var shortcutError: String?
    @State private var isAboutExpanded: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private let compatReport = CompatibilityEngine.shared.evaluateCompatibility()

    public init(controller: AnimationController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBarView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Unsupported hardware banner if needed
                    if !compatReport.isCompatible {
                        unsupportedHardwareBanner
                    }

                    // 1. GENERAL — Preferred Viewing Angle
                    generalSectionView

                    // 2. GLOBAL SHORTCUT — Calibration Hotkey
                    shortcutsSectionView

                    // 3. EFFECT — Visual Style, Radiance, Intensity, Curve
                    effectsSectionView

                    // 4. APPEARANCE — System / Light / Dark
                    appearanceSectionView

                    // 5. PRIVACY & PERMISSIONS — Screen Recording Transparency
                    privacySectionView

                    // 6. ABOUT & ADVANCED OPTIONS (Collapsible)
                    aboutDisclosureView

                    // Footer
                    footerView
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 660)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(settings.appAppearance.colorScheme)
        .onAppear {
            hasScreenRecordingPermission = ScreenCaptureEngine.hasScreenCaptureAccess()
            settings.updateSystemAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasScreenRecordingPermission = ScreenCaptureEngine.hasScreenCaptureAccess()
        }
    }

    // MARK: - Header Bar
    private var headerBarView: some View {
        HStack(spacing: 12) {
            appIconView(size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacHinge")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                Text("Physical Lid-Driven Folding Transition")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Enabled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Toggle("Enabled", isOn: $settings.isEnabled)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel("Enable or disable MacHinge")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Unsupported Hardware Banner
    private var unsupportedHardwareBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                Text("MacHinge isn't supported on this Mac.")
                    .font(.subheadline.bold())
            }
            Text(compatReport.unsupportedReason ?? "MacHinge requires a MacBook with a built-in lid angle sensor.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 1. GENERAL SECTION (Preferred Viewing Angle)
    private var generalSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GENERAL")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 14) {
                // Section Title & Live Lid Angle Badge
                HStack(alignment: .center) {
                    Text("Preferred Viewing Angle")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.primary)

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(String(format: "Lid: %.1f°", controller.displayAngle))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.3), lineWidth: 0.8)
                    )
                    .accessibilityLabel("Current physical lid angle: \(String(format: "%.1f degrees", controller.displayAngle))")
                }

                Text("At this angle, the display remains 100% normal and sharp. The transition begins when you move away from it.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Presets List with HIG Selection Rows
                VStack(spacing: 4) {
                    ForEach(ViewingAnglePreset.allCases) { p in
                        HStack(spacing: 10) {
                            Image(systemName: settings.preset == p ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(settings.preset == p ? .accentColor : .secondary.opacity(0.7))
                                .font(.system(size: 14))

                            Text(p.rawValue)
                                .font(.system(size: 13, weight: settings.preset == p ? .semibold : .regular))
                                .foregroundColor(.primary)

                            Spacer()

                            if let val = p.angleValue {
                                Text(String(format: "%.0f°", val))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(settings.preset == p ? Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(settings.preset == p ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            settings.preset = p
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(p.rawValue), \(settings.preset == p ? "selected" : "not selected")")
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                // Action Row: Set Current Angle Button & Saved Angle Readout
                HStack(alignment: .center) {
                    Button(action: {
                        let angle = round(controller.displayAngle * 10.0) / 10.0
                        settings.setCustomAngleFromCurrentSensor(angle)
                        savedAngleBannerValue = angle
                        showingCalibrationBanner = true
                        CalibrationToastHUD.shared.show(angle: angle)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            showingCalibrationBanner = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "scope")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Set Current Angle (\(String(format: "%.1f°", controller.displayAngle)))")
                                .font(.system(size: 12.5, weight: .medium))
                        }
                    }
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Set current physical lid angle of \(String(format: "%.1f", controller.displayAngle)) degrees as preferred angle")

                    Spacer()

                    Text(String(format: "Saved: %.1f°", settings.effectivePreferredAngle))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }

                if showingCalibrationBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("Preferred angle saved: \(String(format: "%.1f°", savedAngleBannerValue))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .transition(.opacity)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.5), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
        }
    }

    // MARK: - 2. GLOBAL SHORTCUT SECTION
    private var shortcutsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GLOBAL SHORTCUT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 14) {
                // Enable Calibration Hotkey Checkbox
                HStack(spacing: 8) {
                    Button(action: {
                        settings.isHotkeyEnabled.toggle()
                    }) {
                        Image(systemName: settings.isHotkeyEnabled ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15))
                            .foregroundColor(settings.isHotkeyEnabled ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text("Enable Calibration Hotkey")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.primary)
                        .onTapGesture {
                            settings.isHotkeyEnabled.toggle()
                        }

                    Spacer()
                }

                Text("Calibrate and save your current physical lid angle instantly from anywhere without opening settings.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.isHotkeyEnabled {
                    // Row 1: Shortcut, Key Badge, Test Hotkey, Reset
                    HStack(spacing: 10) {
                        Text("Shortcut:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        Button(action: {
                            if isRecordingShortcut {
                                stopShortcutRecording()
                            } else {
                                startShortcutRecording()
                            }
                        }) {
                            HStack(spacing: 6) {
                                if isRecordingShortcut {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 7, height: 7)
                                    Text("Press Keys…")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                } else {
                                    Text(settings.hotkeyCombination.displayString)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isRecordingShortcut ? Color.accentColor.opacity(0.12) : Color(NSColor.windowBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(
                                        isRecordingShortcut
                                            ? Color.accentColor
                                            : Color(NSColor.separatorColor).opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Active shortcut: \(settings.hotkeyCombination.displayString). Click to change.")

                        if isRecordingShortcut {
                            Button("Cancel") {
                                stopShortcutRecording()
                            }
                            .controlSize(.small)
                        } else {
                            Button("Test Hotkey") {
                                controller.saveCurrentSensorAsPreferred()
                                CalibrationToastHUD.shared.show(angle: controller.rawAngle)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Test calibration hotkey")

                            Button("Reset (⌥⌘S)") {
                                settings.hotkeyCombination = .defaultHotkey
                                shortcutError = nil
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Reset shortcut to default")
                        }

                        Spacer()
                    }

                    if let error = shortcutError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }

                    // Row 2: Presets
                    HStack(spacing: 8) {
                        Text("Presets:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        presetShortcutButton(title: "⌥⌘S (Default)", combo: .defaultHotkey)
                        presetShortcutButton(title: "⌃⌥⌘S", combo: .controlOptionCommandS)
                        presetShortcutButton(title: "⇧⌘S", combo: .shiftCommandS)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.5), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
        }
    }

    private func presetShortcutButton(title: String, combo: HotkeyCombination) -> some View {
        Button(action: {
            settings.hotkeyCombination = combo
            shortcutError = nil
        }) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .accessibilityLabel("Set shortcut to \(title)")
    }

    private func startShortcutRecording() {
        isRecordingShortcut = true
        shortcutError = nil
        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let carbonFlags = HotkeyCombination.carbonModifierFlags(from: event.modifierFlags)
            if event.keyCode == 53 && carbonFlags == 0 { // Escape cancels
                self.stopShortcutRecording()
                return nil
            }
            if carbonFlags != 0 {
                let combo = HotkeyCombination(keyCode: UInt32(event.keyCode), carbonModifiers: carbonFlags)
                self.settings.hotkeyCombination = combo
                self.stopShortcutRecording()
                return nil
            } else {
                self.shortcutError = "Include at least one modifier key (⌘, ⌥, ⌃, or ⇧)."
            }
            return event
        }
    }

    private func stopShortcutRecording() {
        isRecordingShortcut = false
        if let monitor = shortcutEventMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutEventMonitor = nil
        }
    }

    // MARK: - 3. EFFECTS SECTION
    private var effectsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 14) {
                // Visual Style Picker
                HStack {
                    Text("Visual Style")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Picker("Visual Style", selection: $settings.visualEffectStyle) {
                        ForEach(VisualEffectStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .frame(width: 240, alignment: .trailing)
                    .accessibilityLabel("Select Visual Effect Style")
                }

                // Glow Radiance Slider
                if settings.visualEffectStyle == .luminousGlow {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Glow Radiance:")
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(String(format: "%.0f%%", settings.glowIntensity * 100))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.glowIntensity, in: 0.2...2.0, step: 0.1)
                            .accessibilityLabel("Glow Radiance")
                            .accessibilityValue("\(Int(settings.glowIntensity * 100)) percent")
                    }
                }

                // Animation Intensity Slider
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Animation Intensity:")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(String(format: "%.0f%%", settings.animationIntensity * 100))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.animationIntensity, in: 0.5...1.5, step: 0.05)
                        .accessibilityLabel("Animation Intensity")
                        .accessibilityValue("\(Int(settings.animationIntensity * 100)) percent")
                }

                // Closed Endpoint Slider
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Closed Endpoint:")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(String(format: "%.1f°", settings.closedEndpointAngle))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.closedEndpointAngle, in: 15...60, step: 1.0)
                        .accessibilityLabel("Closed Endpoint Angle")
                        .accessibilityValue("\(String(format: "%.1f", settings.closedEndpointAngle)) degrees")
                }

                // Transition Curve Picker
                HStack {
                    Text("Transition Curve")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Picker("Transition Curve", selection: $settings.transitionCurve) {
                        ForEach(TransitionCurve.allCases) { curve in
                            Text(curve.rawValue).tag(curve)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .frame(width: 240, alignment: .trailing)
                    .accessibilityLabel("Transition Curve")
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.5), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
        }
    }

    // MARK: - 4. APPEARANCE SECTION
    private var appearanceSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPEARANCE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Theme Mode")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.primary)

                    Spacer()

                    Picker("Appearance", selection: $settings.appAppearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .accessibilityLabel("Select App Appearance Theme")
                }

                Text("Choose whether MacHinge should match your macOS System appearance automatically, or stay locked in Light or Dark mode.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.5), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
        }
    }

    // MARK: - 5. PRIVACY & PERMISSIONS SECTION
    private var privacySectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIVACY & PERMISSIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Screen Recording:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    if hasScreenRecordingPermission {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Allowed")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Not Allowed")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.orange)
                            }

                            Button("Open System Settings") {
                                ScreenCaptureEngine.requestScreenCaptureAccess()
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                Text("Screen content is processed entirely on-device via Apple Metal and is never recorded, saved, uploaded, or sent anywhere.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.5), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
        }
    }

    // MARK: - 6. ABOUT & ADVANCED OPTIONS (Collapsible)
    private var aboutDisclosureView: some View {
        DisclosureGroup(isExpanded: $isAboutExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Divider().padding(.vertical, 4)

                HStack(spacing: 10) {
                    appIconView(size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MacHinge")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Physical Lid-Driven Display Transition")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Text("Version:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0.1.0 (Build 1)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }

                HStack {
                    Text("Architecture:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Built for Apple Silicon (M1–M5)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }

                HStack {
                    Text("Sensor Interface:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Apple SPU HID Lid Angle Sensor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }

                if settings.showDebugControls {
                    HStack {
                        Text("Developer Dashboard:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Open Dashboard…") {
                            MenuBarManager.shared.onOpenDebugStudio?()
                        }
                        .controlSize(.small)
                    }
                }

                Divider().padding(.vertical, 4)

                HStack {
                    Spacer()
                    Button("Reset All Settings to Defaults") {
                        settings.resetToDefaults()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reset All Settings to Defaults")
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text("About & Advanced Options")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.5), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Spacer()
            Text("MacHinge 0.1.0 • Built for Apple Silicon")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary.opacity(0.75))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - App Icon View Helper
    @ViewBuilder
    private func appIconView(size: CGFloat) -> some View {
        if let icon = loadAppIcon() {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 3, x: 0, y: 1.5)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: size, height: size)

                Image(systemName: "laptopcomputer")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.accentColor)
            }
        }
    }

    private static let cachedAppIcon: NSImage? = {
        if let bundleUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: bundleUrl) {
            return img
        }
        if let pngUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: pngUrl) {
            return img
        }
        if let bundlePath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: bundlePath) {
            return img
        }
        if let img = NSImage(contentsOfFile: "AppIcon.png") {
            return img
        }
        if let img = NSImage(contentsOfFile: "AppIcon.icns") {
            return img
        }
        return NSApplication.shared.applicationIconImage
    }()

    private func loadAppIcon() -> NSImage? {
        return Self.cachedAppIcon
    }
}


