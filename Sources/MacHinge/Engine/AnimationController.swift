import Foundation
import AppKit
import Combine
import LidSensorKit

public enum AnimationInputMode: String, CaseIterable, Identifiable {
    case liveSensor = "Real Lid Sensor"
    case simulation = "Manual Simulation"
    case autoSine   = "Auto Oscillation"

    public var id: String { rawValue }
}

@MainActor
public final class AnimationController: ObservableObject {
    public let settings = AppSettings.shared

    @Published public var inputMode: AnimationInputMode = .liveSensor
    @Published public var displayAngle: Double = 105.0
    @Published public var sensorSource: String = "Apple SPU Sensor"
    @Published public var isPipelineIdle: Bool = false

    // Real-time physics state (read directly at 60 FPS by Metal & AnimationController)
    public var rawAngle: Double = 105.0
    public var smoothedAngle: Double = 105.0
    public var progress: Double = 0.0          // 0.0 = 100% normal/sharp -> 1.0 = final fold
    public var angularVelocity: Double = 0.0   // deg/s
    public var progressVelocity: Double = 0.0  // 1/s (> 0 = closing TOP->BTM, < 0 = opening BTM->TOP)
    public var updateHz: Double = 60.0

    // --- Shader Optics Base Multipliers (scaled by settings.animationIntensity) ---
    public var baseCurvature: Double = 1.6
    public var basePerspective: Double = 0.55
    public var baseBlur: Double = 1.2
    public var smoothingFactor: Double = 0.40

    public var onIdleStateChanged: (@MainActor (Bool) -> Void)?

    private var displayLinkTimer: Timer?
    private var sinePhase: Double = 0.0
    private var lastUpdateTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var lastDisplayAngleUpdateTime: TimeInterval = 0.0
    private var idleDuration: TimeInterval = 0.0
    private var previousProgress: Double = 0.0
    private var cancellables = Set<AnyCancellable>()
    private let sensor = LidAngleSensor.shared

    public init() {
        setupSensorSubscription()
        setupSettingsSubscription()
        setupSleepWakeObservers()
        calibrateToInitialAngle()
        if !isPipelineIdle || inputMode == .autoSine {
            startDisplayLinkIfNeeded()
        }
    }

    private func setupSleepWakeObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[AnimationController] Sleep notification -> resetting progress and pausing")
                self?.handleSleep()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[AnimationController] Screen sleep notification -> resetting progress and pausing")
                self?.handleSleep()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[AnimationController] [%.3f] didWakeNotification received", ProcessInfo.processInfo.systemUptime)
                self?.handleWake()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("[AnimationController] [%.3f] screensDidWakeNotification received", ProcessInfo.processInfo.systemUptime)
                self?.handleWake()
            }
        }
    }

    private var hasSnappedFirstReadingAfterWake = false

    private func handleSleep() {
        progress = 0.0
        setIdleState(true)
    }

    private func handleWake() {
        hasSnappedFirstReadingAfterWake = false
        self.calibrateToInitialAngle()
        self.progress = self.computeProgress(for: self.smoothedAngle)
        if self.progress > 0.0001 {
            self.setIdleState(false)
        } else {
            self.setIdleState(true)
        }
    }

    private func calibrateToInitialAngle() {
        if let current = sensor.readCurrentAngle(), current.angle.isFinite, current.angle >= 0.0, current.angle <= 180.0 {
            rawAngle = current.angle
            smoothedAngle = current.angle
            displayAngle = current.angle
        } else {
            rawAngle = settings.effectivePreferredAngle
            smoothedAngle = settings.effectivePreferredAngle
            displayAngle = settings.effectivePreferredAngle
        }
        let initialP = computeProgress(for: smoothedAngle)
        progress = initialP
        previousProgress = initialP
        progressVelocity = 0.0
        if initialP <= 0.0001 {
            isPipelineIdle = true
            idleDuration = 0.5
        } else {
            isPipelineIdle = false
            idleDuration = 0.0
        }
    }

    private func setupSensorSubscription() {
        sensor.onReading = { [weak self] reading in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.inputMode == .liveSensor else { return }

                // Discard invalid or non-finite sensor readings
                guard reading.angleDegrees.isFinite, reading.angleDegrees >= 0.0, reading.angleDegrees <= 180.0 else { return }

                if !self.hasSnappedFirstReadingAfterWake {
                    self.hasSnappedFirstReadingAfterWake = true
                    self.smoothedAngle = reading.angleDegrees
                    self.rawAngle = reading.angleDegrees
                }

                self.rawAngle = reading.angleDegrees
                self.angularVelocity = reading.angularVelocity
                self.updateHz = reading.frequencyHz
                if self.sensorSource != reading.source.rawValue {
                    self.sensorSource = reading.source.rawValue
                }

                self.tick()
            }
        }
    }

    private func setupSettingsSubscription() {
        settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }.store(in: &cancellables)
    }

    public func start() {
        _ = sensor.start(targetHz: 60.0)
    }

    public func stop() {
        displayLinkTimer?.invalidate()
        displayLinkTimer = nil
        sensor.stop()
    }

    public func saveCurrentSensorAsPreferred() {
        if let current = sensor.readCurrentAngle() {
            settings.setCustomAngleFromCurrentSensor(current.angle)
            displayAngle = current.angle
        } else {
            settings.setCustomAngleFromCurrentSensor(smoothedAngle)
            displayAngle = smoothedAngle
        }
        idleDuration = 0.0
        tick()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLinkTimer == nil, !isPipelineIdle || inputMode == .autoSine else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        displayLinkTimer = timer
    }

    private func stopDisplayLink() {
        displayLinkTimer?.invalidate()
        displayLinkTimer = nil
    }

    private func setIdleState(_ idle: Bool) {
        if idle {
            stopDisplayLink()
            ScreenCaptureEngine.shared.pause()
        } else {
            startDisplayLinkIfNeeded()
        }
        guard isPipelineIdle != idle else { return }
        isPipelineIdle = idle
        onIdleStateChanged?(idle)
    }

    public func computeProgress(for angle: Double) -> Double {
        guard settings.isEnabled else { return 0.0 }

        let effectStartAngle: Double = settings.effectStartAngle
        guard angle < effectStartAngle else { return 0.0 }

        let endpoint = settings.closedEndpointAngle
        let activeSpan = max(1.0, effectStartAngle - endpoint)
        let rawX = min(1.0, max(0.0, (effectStartAngle - angle) / activeSpan))

        switch settings.transitionCurve {
        case .smoothstep:
            // S-curve with a responsive gradient so the fold transition is immediately observable past the threshold
            return 0.30 * rawX + 0.70 * (rawX * rawX * (3.0 - 2.0 * rawX))
        case .easeInOut:
            return 0.5 * (1.0 - cos(.pi * rawX))
        case .power14:
            return pow(rawX, 1.4)
        case .linear:
            return rawX
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0.001, now - lastUpdateTime)
        lastUpdateTime = now

        let pref = settings.effectivePreferredAngle
        let endpoint = settings.closedEndpointAngle

        switch inputMode {
        case .liveSensor:
            break

        case .simulation:
            sensorSource = "Manual Simulation"
            updateHz = isPipelineIdle ? 0.0 : 60.0

        case .autoSine:
            sinePhase += dt * 1.5
            let sineNorm = (sin(sinePhase) + 1.0) * 0.5
            let totalRange = max(1.0, pref - endpoint)
            rawAngle = pref - (sineNorm * totalRange)
            sensorSource = "Auto Sine Wave"
            updateHz = 60.0
        }

        // Exponential smoothing filter
        let alpha = min(1.0, max(0.01, smoothingFactor))
        smoothedAngle += (rawAngle - smoothedAngle) * alpha

        // Throttled display angle update for UI
        if abs(rawAngle - displayAngle) >= 0.2 || (now - lastDisplayAngleUpdateTime >= 0.16 && abs(rawAngle - displayAngle) >= 0.05) {
            displayAngle = rawAngle
            lastDisplayAngleUpdateTime = now
        }

        // Continuous full-range progress mapping
        let newProgress = computeProgress(for: smoothedAngle)
        progress = newProgress

        // Compute directional velocity in progress units per second (velocity > 0: closing, velocity < 0: opening)
        let rawVelocity = (newProgress - previousProgress) / dt
        previousProgress = newProgress

        // Filter sensor noise with fast response and instant stop decay
        let velAlpha = min(1.0, dt * 18.0)
        let smoothedVel = progressVelocity + (rawVelocity - progressVelocity) * velAlpha
        if abs(smoothedVel) < 0.015 {
            progressVelocity = 0.0
        } else {
            progressVelocity = smoothedVel
        }

        // Update Overlay Window visibility
        OverlayWindowManager.shared.updateProgressVisibility(progress)

        // Check for Zero-CPU Idle resting state
        if newProgress <= 0.0001 && abs(angularVelocity) < 0.35 && inputMode != .autoSine {
            idleDuration += dt
            if idleDuration >= 0.20 && !isPipelineIdle {
                setIdleState(true)
            }
        } else {
            idleDuration = 0.0
            if isPipelineIdle {
                setIdleState(false)
            }
        }
    }
}
