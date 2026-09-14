import SwiftUI
import LidSensorKit

public struct FirstLaunchView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var controller: AnimationController
    var onComplete: () -> Void

    @State private var currentStep: Int = 1
    @State private var hasPermission: Bool = ScreenCaptureEngine.hasScreenCaptureAccess()
    private let compatReport = CompatibilityEngine.shared.evaluateCompatibility()

    public init(controller: AnimationController, onComplete: @escaping () -> Void) {
        self.controller = controller
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            if currentStep == 1 {
                stepOnePermissionView
            } else {
                stepTwoAngleView
            }
        }
        .frame(width: 520, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = ScreenCaptureEngine.hasScreenCaptureAccess()
        }
    }

    // MARK: - STEP 1: Introduction & Privacy-Transparent Permission
    private var stepOnePermissionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 14) {
                appIconView(size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacHinge")
                        .font(.title2.bold())
                    Text("Your MacBook display responds to the physical hinge.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 8)

            Divider()

            if !compatReport.isCompatible {
                // Unsupported Hardware Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                        Text("MacHinge isn't supported on this Mac.")
                            .font(.headline)
                    }
                    Text(compatReport.unsupportedReason ?? "MacHinge requires a MacBook with a built-in lid angle sensor.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer()

                HStack {
                    Spacer()
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut(.cancelAction)
                }
            } else {
                // Explanatory copy
                VStack(alignment: .leading, spacing: 12) {
                    Text("MacHinge uses your MacBook's lid-angle sensor to drive a visual folding transition as you open and close the lid.")
                        .font(.body)
                        .foregroundColor(.primary)

                    Text("To create the transition, MacHinge needs permission to capture your display locally while the effect is active.")
                        .font(.body)
                        .foregroundColor(.secondary)

                    // Privacy Card
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy Guarantee")
                                .font(.subheadline.bold())
                            Text("Your screen content stays on your Mac. It is not recorded, saved, uploaded, or sent anywhere.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Permission Status & Action
                HStack(spacing: 12) {
                    if hasPermission {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Screen Recording: Allowed")
                                .font(.subheadline.bold())
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Screen Recording: Required")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                        }

                        Spacer()

                        Button("Open Screen Recording Settings") {
                            ScreenCaptureEngine.requestScreenCaptureAccess()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)

                Spacer()

                // Bottom Action
                HStack {
                    Spacer()
                    Button("Continue") {
                        currentStep = 2
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!hasPermission)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
    }

    // MARK: - STEP 2: Preferred Viewing Angle Setup & Calibration
    private var stepTwoAngleView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose your normal viewing angle")
                    .font(.title2.bold())
                Text("At this angle, your display remains completely normal. The folding effect begins when you move away from it.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            Divider()

            // Presets Selection
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ViewingAnglePreset.allCases) { p in
                    HStack {
                        Image(systemName: settings.preset == p ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(settings.preset == p ? .accentColor : .secondary)
                        Text(p.rawValue)
                            .font(.body)
                        Spacer()
                        if let val = p.angleValue {
                            Text(String(format: "%.0f°", val))
                                .font(.subheadline.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.preset = p
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Live Calibration Feedback Card
            let current = controller.displayAngle
            let pref = settings.effectivePreferredAngle
            let diff = abs(current - pref)
            let inDeadband = diff <= settings.deadbandDegrees

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURRENT")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f°", current))
                            .font(.headline.monospaced())
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PREFERRED")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f°", pref))
                            .font(.headline.monospaced())
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DIFFERENCE")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f°", diff))
                            .font(.headline.monospaced())
                    }

                    Spacer()

                    if inDeadband {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Normal display position")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                if settings.preset == .custom {
                    Divider().padding(.vertical, 2)
                    HStack {
                        Button("Set Current Angle (\(String(format: "%.1f°", current)))") {
                            settings.setCustomAngleFromCurrentSensor(current)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Spacer()

                        Text("Current angle saved as anchor")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Bottom Navigation
            HStack {
                Button("Back") {
                    currentStep = 1
                }
                .controlSize(.regular)

                Spacer()

                Button("Get Started") {
                    settings.hasCompletedOnboarding = true
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
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
                .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
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

    private func loadAppIcon() -> NSImage? {
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
        if let appIcon = NSApplication.shared.applicationIconImage {
            return appIcon
        }
        return nil
    }
}
