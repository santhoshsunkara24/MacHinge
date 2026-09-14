import SwiftUI
import MetalKit
import LidSensorKit

public struct DebugStudioView: View {
    @ObservedObject var controller: AnimationController
    @ObservedObject var settings = AppSettings.shared
    @StateObject private var overlayManager = OverlayWindowManager.shared
    @State private var renderer: DuoFoldRenderer?
    @State private var isLiveCaptureEnabled: Bool = false
    private let compatReport = CompatibilityEngine.shared.evaluateCompatibility()

    public init(controller: AnimationController) {
        self.controller = controller
    }

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
                    if controller.isPipelineIdle {
                        HStack(spacing: 6) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("IDLE (0% GPU / PAUSED)")
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
                    .frame(width: 200, height: 6)

                    Text(String(format: "Velocity: %+.1f°/s", controller.angularVelocity))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.85))
                }
                .padding(12)
                .background(Color.black.opacity(0.80))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(28)
            }
            .frame(minWidth: 540, minHeight: 450)

            Divider()

            // Right: Developer Controls & Simulation
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Developer Diagnostics")
                        .font(.headline)
                        .padding(.top, 4)

                    // 1. Fullscreen Desktop Overlay Launcher
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FULLSCREEN OVERLAY")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)

                        if overlayManager.isOverlayActive {
                            Button("Exit Fullscreen Overlay") {
                                overlayManager.hideOverlay()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button("Launch Fullscreen Overlay") {
                                overlayManager.showOverlay()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // 2. Input Source & Simulation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INPUT SOURCE")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $controller.inputMode) {
                            ForEach(AnimationInputMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        if controller.inputMode == .simulation {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Simulated:")
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
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // 3. Telemetry
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LIVE TELEMETRY")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)

                        Group {
                            HStack {
                                Text("Pipeline State:")
                                Spacer()
                                Text(controller.isPipelineIdle ? "IDLE (Paused)" : "ACTIVE (60 FPS)")
                                    .font(.caption2.monospaced().bold())
                                    .foregroundColor(controller.isPipelineIdle ? .blue : .green)
                            }
                            HStack {
                                Text("Sensor Source:")
                                Spacer()
                                Text(controller.sensorSource).font(.caption2.monospaced())
                            }
                            HStack {
                                Text("Sensor Rate:")
                                Spacer()
                                Text(String(format: "%.1f Hz", controller.updateHz)).font(.caption2.monospaced())
                            }
                            HStack {
                                Text("Raw Angle:")
                                Spacer()
                                Text(String(format: "%.2f°", controller.rawAngle)).font(.caption2.monospaced())
                            }
                            HStack {
                                Text("Smoothed Angle:")
                                Spacer()
                                Text(String(format: "%.2f°", controller.smoothedAngle)).font(.caption2.monospaced())
                            }
                            HStack {
                                Text("Active Progress:")
                                Spacer()
                                Text(String(format: "%.3f", controller.progress)).font(.caption2.monospaced().bold())
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
            }
            .frame(width: 320)
        }
        .onAppear {
            ScreenCaptureEngine.shared.onNewTexture = { frame in
                self.renderer?.setTexture(frame.texture)
            }
        }
    }
}
