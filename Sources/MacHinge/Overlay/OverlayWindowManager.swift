import Foundation
import AppKit
import MetalKit
import SwiftUI
import Combine
import LidSensorKit

public struct DiagnosticHUDView: View {
    @ObservedObject var controller: AnimationController
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var capture = ScreenCaptureEngine.shared

    public var body: some View {
        if settings.showDebugControls {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(capture.totalFrameCount > 0 ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("MAC HINGE DEBUG")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(capture.totalFrameCount > 0 ? .green : .orange)
                    Spacer()
                    Text(controller.sensorSource)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }

                Divider().background(Color.white.opacity(0.3))

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow {
                        Text("ANGLE:").bold()
                        Text(String(format: "%6.2f°", controller.rawAngle))
                            .foregroundColor(.yellow)
                        Text("PROGRESS:").bold()
                        Text(String(format: "%5.3f", controller.progress))
                            .foregroundColor(controller.progress > 0.001 ? .cyan : .white.opacity(0.7))
                    }

                    GridRow {
                        Text("CAPTURE:").bold()
                        Text(capture.totalFrameCount > 0 ? String(format: "%.1f fps", capture.measuredFPS) : capture.currentStatus.rawValue)
                            .foregroundColor(capture.totalFrameCount > 0 ? .green : .orange)
                        Text("FRAME SIZE:").bold()
                        Text(capture.lastWidth > 0 ? "\(capture.lastWidth) × \(capture.lastHeight)" : "—")
                            .foregroundColor(.white)
                    }

                    GridRow {
                        Text("TEXTURE:").bold()
                        Text(capture.totalFrameCount > 0 ? "OK (\(capture.totalFrameCount))" : "WAITING")
                            .foregroundColor(capture.totalFrameCount > 0 ? .green : .orange)
                        Text("RENDER:").bold()
                        Text("OK (\(OverlayWindowManager.shared.rendererRenderCount))")
                            .foregroundColor(.green)
                    }

                    GridRow {
                        Text("OVERLAY:").bold()
                        Text(OverlayWindowManager.shared.isOverlayActive ? "VISIBLE" : "HIDDEN")
                            .foregroundColor(OverlayWindowManager.shared.isOverlayActive ? .green : .red)
                        Text("DISPLAY ID:").bold()
                        Text(capture.activeDisplayID > 0 ? "\(capture.activeDisplayID)" : "1 (Built-in)")
                            .foregroundColor(.white)
                    }

                    GridRow {
                        Text("BUILT-IN:").bold()
                        Text("YES")
                            .foregroundColor(.green)
                        Text("BLUR DIR:").bold()
                        Text(controller.progressVelocity > 0.035 ? "▼ TOP→BTM" : (controller.progressVelocity < -0.035 ? "▲ BTM→TOP" : "— SHARP"))
                            .foregroundColor(abs(controller.progressVelocity) > 0.035 ? .cyan : .white.opacity(0.7))
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
            )
            .frame(width: 380)
            .padding(16)
        }
    }
}

@MainActor
public final class OverlayWindowManager: ObservableObject {
    public static let shared = OverlayWindowManager()

    @Published public var isOverlayActive: Bool = false

    private var overlayWindow: NSWindow?
    private var overlayMTKView: MTKView?
    private var overlayRenderer: DuoFoldRenderer?
    private var hudHostingView: NSHostingView<DiagnosticHUDView>?
    private var cancellables = Set<AnyCancellable>()

    public var rendererRenderCount: Int {
        return overlayRenderer?.renderCount ?? 0
    }

    public static func findBuiltinScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if let screenNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if CGDisplayIsBuiltin(screenNum) != 0 {
                    return screen
                }
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    public func setupOverlay(with animationController: AnimationController) {
        guard let screen = OverlayWindowManager.findBuiltinScreen() else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.overlayWindow)))
        window.ignoresMouseEvents = true // CLICK-THROUGH
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.alphaValue = (animationController.progress > 0.0001) ? 1.0 : 0.0
        window.orderFrontRegardless()

        // Container view
        let containerView = NSView(frame: screen.frame)
        containerView.autoresizingMask = [.width, .height]

        // Metal View
        let mtkView = MTKView(frame: screen.frame)
        mtkView.autoresizingMask = [.width, .height]

        if let renderer = DuoFoldRenderer(metalKitView: mtkView) {
            renderer.animationController = animationController
            self.overlayRenderer = renderer
        }

        containerView.addSubview(mtkView)

        window.contentView = containerView
        self.overlayWindow = window
        self.overlayMTKView = mtkView

        // Connect ScreenCaptureKit texture directly to overlay renderer
        ScreenCaptureEngine.shared.onNewTexture = { [weak self] frame in
            self?.overlayRenderer?.setTexture(frame)
        }

        func updateHUDState() {
            if AppSettings.shared.showDebugControls {
                if self.hudHostingView == nil, let screen = OverlayWindowManager.findBuiltinScreen() {
                    let hudView = DiagnosticHUDView(controller: animationController)
                    let hosting = NSHostingView(rootView: hudView)
                    hosting.frame = NSRect(x: screen.frame.width - 410, y: screen.frame.height - 180, width: 400, height: 170)
                    hosting.autoresizingMask = [.minXMargin, .minYMargin]
                    containerView.addSubview(hosting)
                    self.hudHostingView = hosting
                }
            } else {
                self.hudHostingView?.removeFromSuperview()
                self.hudHostingView = nil
            }
        }

        updateHUDState()

        AppSettings.shared.objectWillChange.sink { _ in
            Task { @MainActor in
                updateHUDState()
            }
        }.store(in: &cancellables)

        setupLifecycleObservers()
        if animationController.progress > 0.0001 {
            let winID = getOverlayWindowID()
            let excluded = winID != nil ? [winID!] : []
            Task {
                await ScreenCaptureEngine.shared.startCapture(excludingWindowIDs: excluded)
            }
            showOverlay()
        } else {
            hideOverlay()
        }
    }

    private func setupLifecycleObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[OverlayWindowManager] Sleep notification -> hiding overlay & clearing textures")
                self?.handleSleep()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[OverlayWindowManager] Screen sleep notification -> hiding overlay & clearing textures")
                self?.handleSleep()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[OverlayWindowManager] Wake notification -> refreshing window frame")
                self?.handleWake()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[OverlayWindowManager] Screen wake notification -> refreshing window frame")
                self?.handleWake()
            }
        }

        // Screen parameter changes
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWake()
            }
        }
    }

    private func handleSleep() {
        NSLog("[OverlayWindowManager] [%.3f] handleSleep -> hiding overlay", ProcessInfo.processInfo.systemUptime)
        overlayWindow?.alphaValue = 0.0
        overlayWindow?.orderOut(nil)
        isOverlayActive = false
        overlayRenderer?.setPaused(true)
        ScreenCaptureEngine.shared.pause()
    }

    private func handleWake() {
        guard let screen = OverlayWindowManager.findBuiltinScreen() else { return }
        overlayWindow?.setFrame(screen.frame, display: true)
        overlayMTKView?.frame = screen.frame
        hudHostingView?.frame = NSRect(x: screen.frame.width - 410, y: screen.frame.height - 180, width: 400, height: 170)
        NSLog("[OverlayWindowManager] Screen wake -> refreshed window frame")
    }

    public func getOverlayWindowID() -> CGWindowID? {
        guard let window = overlayWindow else { return nil }
        return CGWindowID(window.windowNumber)
    }

    public func showOverlay() {
        guard let window = overlayWindow else { return }
        window.alphaValue = 1.0
        window.orderFrontRegardless()
        isOverlayActive = true
        overlayRenderer?.setPaused(false)

        let winID = getOverlayWindowID()
        let excluded = winID != nil ? [winID!] : []
        Task {
            if ScreenCaptureEngine.shared.currentStatus == .notAuthorized || ScreenCaptureEngine.shared.currentStatus == .failed {
                await ScreenCaptureEngine.shared.startCapture(excludingWindowIDs: excluded)
            }
        }
    }

    public func hideOverlay() {
        guard let window = overlayWindow else { return }
        window.alphaValue = 0.0
        isOverlayActive = false
        overlayRenderer?.setPaused(true)
    }

    public func updateProgressVisibility(_ progress: Double) {
        guard let window = overlayWindow else { return }
        if progress > 0.0001 {
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            if window.alphaValue < 1.0 {
                window.alphaValue = 1.0
            }
            if overlayRenderer?.isPaused == true {
                overlayRenderer?.setPaused(false)
            }
            isOverlayActive = true
            if ScreenCaptureEngine.shared.currentStatus != .streaming && ScreenCaptureEngine.shared.currentStatus != .initializing {
                let winID = getOverlayWindowID()
                let excluded = winID != nil ? [winID!] : []
                Task {
                    await ScreenCaptureEngine.shared.startCapture(excludingWindowIDs: excluded)
                }
            }
        } else {
            if window.alphaValue > 0.0 {
                window.alphaValue = 0.0
            }
            if overlayRenderer?.isPaused == false {
                overlayRenderer?.setPaused(true)
            }
            isOverlayActive = false
            if ScreenCaptureEngine.shared.currentStatus == .streaming {
                ScreenCaptureEngine.shared.pause()
            }
        }
    }
}
