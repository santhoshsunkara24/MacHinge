import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import Metal
import AppKit

public final class CapturedFrame: @unchecked Sendable {
    public let texture: MTLTexture
    public let cvTexture: CVMetalTexture?
    public let width: Int
    public let height: Int
    public let timestamp: TimeInterval

    public init(texture: MTLTexture, cvTexture: CVMetalTexture? = nil, width: Int, height: Int, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.texture = texture
        self.cvTexture = cvTexture
        self.width = width
        self.height = height
        self.timestamp = timestamp
    }
}

public enum ScreenCaptureStatus: String, Sendable {
    case notAuthorized = "Permission Required"
    case initializing  = "Starting Stream..."
    case streaming     = "Capturing Live Desktop"
    case paused        = "Stream Paused (Sleep/Idle)"
    case failed        = "Capture Unavailable"
}

public final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, ObservableObject, @unchecked Sendable {
    public static let shared = ScreenCaptureEngine()

    private var stream: SCStream?
    private var textureCache: CVMetalTextureCache?
    private let device: MTLDevice
    private let captureQueue = DispatchQueue(label: "com.machinge.screencapture", qos: .userInteractive)

    public var onNewTexture: (@MainActor @Sendable (CapturedFrame) -> Void)?
    public var onStatusChange: (@MainActor @Sendable (ScreenCaptureStatus) -> Void)?

    // Frame metrics for live diagnostics
    public private(set) var totalFrameCount: Int = 0
    public private(set) var measuredFPS: Double = 0.0
    public private(set) var lastWidth: Int = 0
    public private(set) var lastHeight: Int = 0
    public private(set) var activeDisplayID: CGDirectDisplayID = 0
    public private(set) var isBuiltinDisplay: Bool = false
    @Published public private(set) var currentStatus: ScreenCaptureStatus = .initializing

    private var fpsFrameCount: Int = 0
    private var lastFpsTimestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var isPaused: Bool = false

    private var permissionRetryTimer: DispatchSourceTimer?
    private var cachedExcludingIDs: [CGWindowID] = []

    public override init() {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = defaultDevice
        super.init()

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        setupLifecycleObservers()
    }

    nonisolated(unsafe) private static var hasRequestedPermission = false

    public static func hasScreenCaptureAccess() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenCaptureAccess(force: Bool = false) {
        if force || !hasRequestedPermission {
            hasRequestedPermission = true
            _ = CGRequestScreenCaptureAccess()
        }
    }

    public func startCapture(excludingWindowIDs: [CGWindowID] = []) async {
        if stream != nil && !isPaused { return }
        self.cachedExcludingIDs = excludingWindowIDs
        self.isPaused = false

        guard ScreenCaptureEngine.hasScreenCaptureAccess() else {
            NSLog("[ScreenCaptureEngine] Screen recording permission not yet granted.")
            ScreenCaptureEngine.requestScreenCaptureAccess()
            updateStatus(.notAuthorized)
            startPermissionRetryTimer()
            return
        }

        stopPermissionRetryTimer()
        updateStatus(.initializing)

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            NSLog("[ScreenCaptureEngine] Shareable content displays: %d, windows: %d", content.displays.count, content.windows.count)

            // Target the internal MacBook display where the physical lid sensor is located
            let targetDisplay = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? content.displays.first
            guard let display = targetDisplay else {
                NSLog("[ScreenCaptureEngine] No display found in shareable content")
                updateStatus(.failed)
                return
            }

            let isBuiltin = (CGDisplayIsBuiltin(display.displayID) != 0)
            let displayID = display.displayID
            Task { @MainActor in
                self.activeDisplayID = displayID
                self.isBuiltinDisplay = isBuiltin
            }
            NSLog("[ScreenCaptureEngine] Selected Display: ID=%u, Builtin=%d, Size=%dx%d", display.displayID, isBuiltin ? 1 : 0, display.width, display.height)

            // Exclude our application windows to prevent recursion
            let excludedWindows = content.windows.filter { win in
                excludingWindowIDs.contains(win.windowID) || win.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }

            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

            // Dynamically query backing scale factor for display
            let matchingScreen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
            })
            let scale = max(1, Int(matchingScreen?.backingScaleFactor ?? 2.0))

            let config = SCStreamConfiguration()
            config.width = display.width * scale
            config.height = display.height * scale
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false // DO NOT bake cursor into captured frames - macOS hardware cursor renders on top with 0 latency
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS
            config.queueDepth = 3

            let scStream = SCStream(filter: filter, configuration: config, delegate: self)
            try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            try await scStream.startCapture()

            self.stream = scStream
            updateStatus(.streaming)
            NSLog("[ScreenCaptureEngine] SCStream started successfully (%dx%d @ 60 FPS, showsCursor=false)", config.width, config.height)

            // Capture initial snapshot immediately so Metal has a live texture with zero latency
            if let initialBuffer = try? await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) {
                if let imageBuffer = CMSampleBufferGetImageBuffer(initialBuffer) {
                    NSLog("[ScreenCaptureEngine] Initial snapshot captured (%dx%d)", CVPixelBufferGetWidth(imageBuffer), CVPixelBufferGetHeight(imageBuffer))
                    self.processImageBuffer(imageBuffer)
                }
            }
        } catch {
            NSLog("[ScreenCaptureEngine] ScreenCaptureKit error: %@", "\(error)")
            updateStatus(.failed)
            scheduleStreamRecovery()
        }
    }

    private var isRestartingCapture = false

    private func setupLifecycleObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            NSLog("[ScreenCaptureEngine] Sleep notification received -> pausing capture")
            self?.pause()
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            NSLog("[ScreenCaptureEngine] Display sleep notification received -> pausing capture")
            self?.pause()
        }
        wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWake()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWake()
            }
        }
    }

    @MainActor
    private func handleWake() {
        isPaused = false
        Task { @MainActor in
            await self.restartCapture()
        }
    }

    @MainActor
    public func restartCapture() async {
        guard !isRestartingCapture else { return }
        isRestartingCapture = true
        defer { isRestartingCapture = false }

        NSLog("[ScreenCaptureEngine] Restarting capture stream...")
        await stopCapture()
        await startCapture(excludingWindowIDs: cachedExcludingIDs)
    }

    private var recoveryTimer: DispatchSourceTimer?
    private func scheduleStreamRecovery() {
        guard recoveryTimer == nil, !isPaused else { return }
        NSLog("[ScreenCaptureEngine] Scheduling stream recovery in 500ms...")
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(deadline: .now() + 0.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.recoveryTimer?.cancel()
            self.recoveryTimer = nil
            Task { @MainActor in
                await self.restartCapture()
            }
        }
        timer.resume()
        recoveryTimer = timer
    }

    private func startPermissionRetryTimer() {
        guard permissionRetryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if ScreenCaptureEngine.hasScreenCaptureAccess() {
                Task {
                    await self.startCapture(excludingWindowIDs: self.cachedExcludingIDs)
                }
            }
        }
        timer.resume()
        permissionRetryTimer = timer
    }

    private func stopPermissionRetryTimer() {
        permissionRetryTimer?.cancel()
        permissionRetryTimer = nil
    }

    public func stopCapture() async {
        if let scStream = stream {
            do {
                try await scStream.stopCapture()
            } catch {
                NSLog("[ScreenCaptureEngine] Error stopping stream: %@", "\(error)")
            }
            self.stream = nil
        }
        updateStatus(.notAuthorized)
    }

    public func suspendProcessing() {
        // Keeps the capture stream alive so textures are always instantly available
    }

    public func resumeProcessing() {
        if stream == nil {
            Task {
                await startCapture(excludingWindowIDs: cachedExcludingIDs)
            }
        }
    }

    public func pause() {
        guard !isPaused || stream != nil else { return }
        isPaused = true
        updateStatus(.paused)
        if let scStream = stream {
            self.stream = nil
            Task {
                try? await scStream.stopCapture()
            }
        }
    }

    @MainActor
    public func resume() {
        isPaused = false
        handleWake()
    }

    private func updateStatus(_ status: ScreenCaptureStatus) {
        Task { @MainActor in
            self.currentStatus = status
            self.onStatusChange?(status)
        }
    }

    // MARK: - SCStreamOutput
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isPaused, type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processImageBuffer(imageBuffer)
    }

    private func processImageBuffer(_ imageBuffer: CVImageBuffer) {
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        guard let cache = textureCache else { return }

        var cvTextureOut: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            imageBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTextureOut
        )

        if result == kCVReturnSuccess, let cvTexture = cvTextureOut, let metalTexture = CVMetalTextureGetTexture(cvTexture) {
            let now = ProcessInfo.processInfo.systemUptime
            self.fpsFrameCount += 1

            let elapsed = now - self.lastFpsTimestamp
            let newFPS: Double?
            if elapsed >= 1.0 {
                newFPS = Double(self.fpsFrameCount) / elapsed
                self.fpsFrameCount = 0
                self.lastFpsTimestamp = now
            } else {
                newFPS = nil
            }

            let frame = CapturedFrame(texture: metalTexture, cvTexture: cvTexture, width: width, height: height, timestamp: now)

            Task { @MainActor in
                self.totalFrameCount += 1
                self.lastWidth = width
                self.lastHeight = height
                if let fps = newFPS {
                    self.measuredFPS = fps
                }
                self.onNewTexture?(frame)
            }
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[ScreenCaptureEngine] ScreenCapture stream didStopWithError: %@", "\(error)")
        updateStatus(.failed)
        if !isPaused {
            scheduleStreamRecovery()
        }
    }
}
