import SwiftUI
import MetalKit
import LidSensorKit

struct MetalViewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: AnimationController
    @Binding var renderer: DuoFoldRenderer?

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        if let createdRenderer = DuoFoldRenderer(metalKitView: mtkView) {
            createdRenderer.animationController = controller
            DispatchQueue.main.async {
                self.renderer = createdRenderer
            }
        }
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
    }
}

public struct MainAppView: View {
    @StateObject private var controller = AnimationController()
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var overlayManager = OverlayWindowManager.shared
    @State private var renderer: DuoFoldRenderer?
    @State private var compatReport: CompatibilityReport = CompatibilityEngine.shared.evaluateCompatibility()
    @State private var hasPermission: Bool = ScreenCaptureEngine.hasScreenCaptureAccess()
    @State private var isLiveCaptureEnabled: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Left: Metal Viewport Preview
            ZStack(alignment: .topTrailing) {
                MetalViewRepresentable(controller: controller, renderer: $renderer)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(16)

                // On-screen Status Badges
                VStack(alignment: .trailing, spacing: 6) {
                    if !settings.isEnabled {
                        HStack(spacing: 6) {
                            Circle().fill(Color.gray).frame(width: 8, height: 8)
                            Text("DISABLED")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                    } else if controller.isPipelineIdle {
                        HStack(spacing: 6) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("IDLE (0% GPU / NORMAL DISPLAY)")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                    } else if controller.progress <= 0.0001 {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("100% NORMAL SHARP DISPLAY")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text(String(format: "DUO TRANSITION: %.1f%%", controller.progress * 100))
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                    }

                    Text(String(format: "Angle: %.2f°", controller.smoothedAngle))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundColor(.white)

                    Text(String(format: "Preferred: %.1f° (Δ %+.1f°)",
                                settings.effectivePreferredAngle,
                                controller.smoothedAngle - settings.effectivePreferredAngle))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(controller.progress))), height: 6)
                        }
                    }
                    .frame(width: 220, height: 6)

                    Text(String(format: "Velocity: %+.1f°/s", controller.angularVelocity))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.85))
                }
                .padding(12)
                .background(Color.black.opacity(0.80))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(28)
            }
            .frame(minWidth: 540, minHeight: 480)

            Divider()

            // Right: Product Settings & Controls
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header with Enable Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MacHinge")
                                .font(.title2.bold())
                            Text("iPhone Duo-style Lid Animation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.isEnabled)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    .padding(.top, 4)

                    // Hardware Compatibility Banner if unsupported
                    if !compatReport.isCompatible {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundColor(.red)
                                Text("Unsupported Mac Hardware")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.red)
                            }
                            Text(compatReport.unsupportedReason ?? "Lid angle sensor is unavailable on this device.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 1. PREFERRED VIEWING ANGLE (First-Class Setting)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("PREFERRED VIEWING ANGLE")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text(String(format: "Lid: %.1f°", controller.rawAngle))
                                    .font(.caption2.monospaced().bold())
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                        }

                        Text("Select your comfortable resting angle where the display remains 100% normal and sharp:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Presets
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ViewingAnglePreset.allCases) { p in
                                HStack {
                                    Image(systemName: settings.preset == p ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(settings.preset == p ? .blue : .secondary)
                                    Text(p.rawValue)
                                        .font(.subheadline)
                                    Spacer()
                                    if let val = p.angleValue {
                                        Text(String(format: "%.0f°", val))
                                            .font(.caption.monospaced())
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    settings.preset = p
                                }
                            }
                        }

                        // Custom Angle controls if Custom selected
                        if settings.preset == .custom {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Custom Angle:")
                                    Spacer()
                                    Text(String(format: "%.1f°", settings.customPreferredAngle))
                                        .font(.system(.body, design: .monospaced, weight: .bold))
                                }
                                Slider(value: $settings.customPreferredAngle, in: 75...130, step: 0.5)

                                Button(action: {
                                    controller.saveCurrentSensorAsPreferred()
                                }) {
                                    HStack {
                                        Image(systemName: "scope")
                                        Text("Set Current Lid Angle (\(String(format: "%.1f°", controller.rawAngle)))")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color.blue.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 2. FULLSCREEN OVERLAY CONTROLS
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FULLSCREEN DESKTOP OVERLAY")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)

                        if overlayManager.isOverlayActive {
                            Button(action: {
                                overlayManager.hideOverlay()
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Exit Fullscreen Overlay")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .controlSize(.regular)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button(action: {
                                overlayManager.showOverlay()
                            }) {
                                HStack {
                                    Image(systemName: "macwindow.on.rectangle")
                                    Text("Launch Fullscreen Overlay")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .controlSize(.regular)
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }

                        Text("• 100% Click-through: interacts seamlessly with all apps\n• Zero GPU / Transparent at preferred viewing angle\n• Press ESC in MacHinge window to exit")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 3. MOTION & RANGE PREFERENCES
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ANIMATION & MOTION")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Animation Intensity:")
                                Spacer()
                                Text(String(format: "%.0f%%", settings.animationIntensity * 100))
                                    .font(.caption.monospaced())
                            }
                            Slider(value: $settings.animationIntensity, in: 0.5...1.5, step: 0.05)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Closed Endpoint Angle:")
                                Spacer()
                                Text(String(format: "%.1f°", settings.closedEndpointAngle))
                                    .font(.caption.monospaced())
                            }
                            Slider(value: $settings.closedEndpointAngle, in: 0...30, step: 0.5)
                        }

                        Picker("Response Curve", selection: $settings.transitionCurve) {
                            ForEach(TransitionCurve.allCases) { curve in
                                Text(curve.rawValue).tag(curve)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 4. HARDWARE & COMPATIBILITY INFO
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SYSTEM COMPATIBILITY")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)

                        Group {
                            HStack {
                                Text("Mac Model:")
                                Spacer()
                                Text(compatReport.macModel).font(.caption2.monospaced())
                            }
                            HStack {
                                Text("Architecture:")
                                Spacer()
                                Text(compatReport.cpuArchitecture).font(.caption2.monospaced())
                            }
                            HStack {
                                Text("Lid HID Sensor:")
                                Spacer()
                                Text(compatReport.hasLidSensor ? "Available (Usage 0x008A)" : "Not Found")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(compatReport.hasLidSensor ? .green : .red)
                            }
                            HStack {
                                Text("High Precision:")
                                Spacer()
                                Text(compatReport.hasHighPrecisionSensor ? "0.01° (Usage 0x0545)" : "Standard 1.0°")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 5. DEVELOPER & SIMULATION TOOLS (Collapsible)
                    DisclosureGroup("Developer & Simulation Tools", isExpanded: $settings.showDebugControls) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Input Source", selection: $controller.inputMode) {
                                ForEach(AnimationInputMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())

                            if controller.inputMode == .simulation {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Simulated Angle:")
                                        Spacer()
                                        Text(String(format: "%.1f° (%.1f%%)", controller.rawAngle, controller.progress * 100))
                                            .font(.caption.monospaced().bold())
                                    }
                                    Slider(value: $controller.rawAngle,
                                           in: (settings.closedEndpointAngle - 2)...(settings.effectivePreferredAngle + 10))

                                    HStack(spacing: 4) {
                                        Button("Pref") { controller.rawAngle = settings.effectivePreferredAngle }
                                        Spacer()
                                        Button("81°") { controller.rawAngle = 81.0 }
                                        Spacer()
                                        Button("60°") { controller.rawAngle = 60.0 }
                                        Spacer()
                                        Button("40°") { controller.rawAngle = 40.0 }
                                        Spacer()
                                        Button("End") { controller.rawAngle = settings.closedEndpointAngle }
                                    }
                                    .controlSize(.mini)
                                }
                            }

                            // Telemetry
                            Group {
                                HStack {
                                    Text("Pipeline State:")
                                    Spacer()
                                    Text(controller.isPipelineIdle ? "IDLE (Paused)" : "ACTIVE")
                                        .font(.caption2.monospaced().bold())
                                        .foregroundColor(controller.isPipelineIdle ? .blue : .green)
                                }
                                HStack {
                                    Text("Sensor Rate:")
                                    Spacer()
                                    Text(String(format: "%.1f Hz", controller.updateHz)).font(.caption2.monospaced())
                                }
                                HStack {
                                    Text("Active Progress:")
                                    Spacer()
                                    Text(String(format: "%.3f", controller.progress)).font(.caption2.monospaced())
                                }
                            }

                            Button("Reset All Settings to Defaults") {
                                settings.resetToDefaults()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(16)
            }
            .frame(width: 360)
        }
        .onAppear {
            controller.start()
            overlayManager.setupOverlay(with: controller)

            ScreenCaptureEngine.shared.onNewTexture = { frame in
                self.renderer?.setTexture(frame.texture)
            }
        }
        .onDisappear {
            controller.stop()
            overlayManager.hideOverlay()
        }
    }
}
