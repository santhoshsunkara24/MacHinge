import Foundation
import IOKit
import IOKit.hid
import AppKit

public enum LidSensorSource: String, Sendable {
    case highPrecision = "0.01° (Usage 0x0545)"
    case standard      = "1.00° (Usage 0x047F)"
}

public struct LidReading: Sendable {
    public let angleDegrees: Double         // Continuous angle in degrees
    public let timestamp: TimeInterval      // System uptime
    public let deltaAngle: Double           // Change in degrees since last update
    public let angularVelocity: Double      // Degrees per second
    public let frequencyHz: Double          // Measured update frequency
    public let source: LidSensorSource      // Data source

    public init(
        angleDegrees: Double,
        timestamp: TimeInterval,
        deltaAngle: Double,
        angularVelocity: Double,
        frequencyHz: Double,
        source: LidSensorSource
    ) {
        self.angleDegrees = angleDegrees
        self.timestamp = timestamp
        self.deltaAngle = deltaAngle
        self.angularVelocity = angularVelocity
        self.frequencyHz = frequencyHz
        self.source = source
    }
}

public final class LidAngleSensor: @unchecked Sendable {
    public static let shared = LidAngleSensor()

    private var hidManager: IOHIDManager?
    private var matchedDevice: IOHIDDevice?
    private var pollTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.machinge.lidsensor", qos: .userInteractive)

    private var lastAngle: Double?
    private var lastTimestamp: TimeInterval = 0
    private var sampleCount: Int = 0
    private var lastRateTimestamp: TimeInterval = 0
    private var currentFrequencyHz: Double = 0.0
    private var isSuspended: Bool = false
    private var isPollingActive: Bool = false
    private var stationaryCount: Int = 0
    private var targetIntervalMs: Int = 16
    private var lastEmittedTimestamp: TimeInterval = 0

    private var sleepObservers: [NSObjectProtocol] = []

    public var onReading: ((LidReading) -> Void)?

    public init() {
        setupSleepWakeObservers()
    }

    deinit {
        stop()
        removeSleepWakeObservers()
    }

    public func start(targetHz: Double = 60.0) -> Bool {
        guard hidManager == nil else { return true }

        let hz = max(1.0, min(120.0, targetHz))
        self.targetIntervalMs = max(1, Int(1000.0 / hz))

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDDeviceUsagePageKey as String: 0x0020,
            kIOHIDDeviceUsageKey as String: 0x008A
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        let matchCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let sensor = Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue()
            sensor.matchedDevice = device
        }

        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            return false
        }

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let first = devices.first {
            matchedDevice = first
        }

        // Register event-driven hardware interrupt callback
        let valueCallback: IOHIDValueCallback = { context, result, sender, value in
            guard let context = context else { return }
            let sensor = Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue()
            sensor.handleHardwareInterrupt(value)
        }
        IOHIDManagerRegisterInputValueCallback(manager, valueCallback, context)

        // Read initial state and start active polling
        startHighFrequencyPolling()
        return true
    }

    public func stop() {
        stopHighFrequencyPolling()

        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        matchedDevice = nil
    }

    public func pause() {
        isSuspended = true
        stopHighFrequencyPolling()
    }

    public func resume() {
        isSuspended = false
        matchedDevice = nil
        startHighFrequencyPolling()
    }

    // STRICTLY READ-ONLY
    public func readCurrentAngle() -> (angle: Double, source: LidSensorSource)? {
        guard !isSuspended else { return nil }
        guard let dev = matchedDevice ?? getFirstDevice() else { return nil }

        // 1. Try High Precision Report 7 (Usage 0x0545)
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let ret7 = IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, 7, &report, &length)
        if ret7 == kIOReturnSuccess && length >= 3 {
            let raw = UInt16(report[1]) | (UInt16(report[2]) << 8)
            let angle = Double(raw) / 100.0
            if angle > 0.0 && angle <= 360.0 {
                return (angle, .highPrecision)
            }
        }

        // 2. Fallback to Standard Report 1 (Usage 0x047F)
        var report1 = [UInt8](repeating: 0, count: 8)
        var length1 = report1.count
        let ret1 = IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, 1, &report1, &length1)
        if ret1 == kIOReturnSuccess && length1 >= 2 {
            let angle = Double(report1[1])
            return (angle, .standard)
        }

        // If IOKit report fails, invalidate device pointer to force fresh re-enumeration
        self.matchedDevice = nil
        return nil
    }

    private func getFirstDevice() -> IOHIDDevice? {
        guard let manager = hidManager else { return nil }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        matchedDevice = devices.first
        return matchedDevice
    }

    private var currentIntervalMs: Int = 16

    private func startHighFrequencyPolling() {
        queue.async { [weak self] in
            guard let self = self, !self.isPollingActive, !self.isSuspended else { return }
            self.isPollingActive = true
            self.currentIntervalMs = self.targetIntervalMs
            self.scheduleTimer(intervalMs: self.currentIntervalMs)
        }
    }

    private func scheduleTimer(intervalMs: Int) {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMs), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.pollSensor()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopHighFrequencyPolling() {
        queue.async { [weak self] in
            guard let self = self, self.isPollingActive else { return }
            self.pollTimer?.cancel()
            self.pollTimer = nil
            self.isPollingActive = false
        }
    }

    private func pollSensor() {
        guard !isSuspended else { return }
        guard let (angle, source) = readCurrentAngle() else { return }
        processNewAngle(angle, source: source)
    }

    // Hardware interrupt callback: wakes high-frequency polling immediately on physical movement
    private func handleHardwareInterrupt(_ value: IOHIDValue) {
        guard !isSuspended else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stationaryCount = 0
            if self.currentIntervalMs != self.targetIntervalMs {
                self.currentIntervalMs = self.targetIntervalMs
                self.scheduleTimer(intervalMs: self.currentIntervalMs)
            }
            self.pollSensor()
        }
    }

    private var smoothedVelocity: Double = 0.0

    private func processNewAngle(_ angle: Double, source: LidSensorSource) {
        let now = ProcessInfo.processInfo.systemUptime

        let deltaAngle: Double
        let instantVelocity: Double

        if let last = lastAngle, lastTimestamp > 0 {
            let dt = max(0.0001, now - lastTimestamp)
            deltaAngle = angle - last
            instantVelocity = deltaAngle / dt
            smoothedVelocity += (instantVelocity - smoothedVelocity) * 0.20
        } else {
            deltaAngle = 0.0
            instantVelocity = 0.0
            smoothedVelocity = 0.0
        }

        lastAngle = angle
        lastTimestamp = now

        // Multi-tier adaptive polling interval based on physical movement
        if abs(deltaAngle) < 0.02 && abs(smoothedVelocity) < 0.25 {
            stationaryCount += 1
            if stationaryCount > 60 && currentIntervalMs != 50 {
                currentIntervalMs = 50 // Relax to 20Hz when deeply stationary
                scheduleTimer(intervalMs: currentIntervalMs)
            } else if stationaryCount > 20 && stationaryCount <= 60 && currentIntervalMs != 33 {
                currentIntervalMs = 33 // Relax to 30Hz when briefly stationary
                scheduleTimer(intervalMs: currentIntervalMs)
            }
        } else {
            if stationaryCount > 0 || currentIntervalMs != targetIntervalMs {
                stationaryCount = 0
                currentIntervalMs = targetIntervalMs // Fast 60Hz immediately on movement
                scheduleTimer(intervalMs: currentIntervalMs)
            }
        }

        sampleCount += 1
        let elapsed = now - lastRateTimestamp
        if elapsed >= 0.5 {
            currentFrequencyHz = Double(sampleCount) / elapsed
            sampleCount = 0
            lastRateTimestamp = now
        }

        let reading = LidReading(
            angleDegrees: angle,
            timestamp: now,
            deltaAngle: deltaAngle,
            angularVelocity: smoothedVelocity,
            frequencyHz: currentFrequencyHz,
            source: source
        )

        onReading?(reading)
    }

    private func setupSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        let willSleep = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pause()
        }
        let screensSleep = nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pause()
        }
        let didWake = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }
        let screensWake = nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }

        sleepObservers = [willSleep, screensSleep, didWake, screensWake]
    }

    private func removeSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in sleepObservers {
            nc.removeObserver(obs)
        }
        sleepObservers.removeAll()
    }
}
