import Testing
import Foundation
@testable import MacHinge
@testable import LidSensorKit

@Suite("MacHinge Tests")
struct MacHingeTests {

    @Test("Progress at preferred angle is exactly zero")
    @MainActor
    func testProgressAtPreferredAngleIsExactlyZero() {
        let controller = AnimationController()
        controller.settings.preset = .comfortable105
        controller.settings.deadbandDegrees = 1.0

        let pPref = controller.computeProgress(for: 105.0)
        #expect(abs(pPref - 0.0) < 0.0001)

        let pWithinDeadband = controller.computeProgress(for: 104.5)
        #expect(abs(pWithinDeadband - 0.0) < 0.0001)
    }

    @Test("Closing trigger threshold at 78 degrees")
    @MainActor
    func testClosingTriggerThresholdAt78Degrees() {
        let controller = AnimationController()
        controller.settings.preset = .comfortable105
        controller.settings.closingTriggerAngle = 78.0
        controller.settings.closedEndpointAngle = 25.0

        // Angles strictly above 78° must return exactly 0 progress
        let aboveAngles = [120.0, 105.0, 104.5, 100.0, 90.0, 80.0, 78.1]
        for angle in aboveAngles {
            let p = controller.computeProgress(for: angle)
            #expect(abs(p - 0.0) < 0.0001, "Angle \(angle)° (> 78°) must have 0.0 progress")
        }

        // Exactly 78.0° must return exactly 0 progress
        let pAtThreshold = controller.computeProgress(for: 78.0)
        #expect(abs(pAtThreshold - 0.0) < 0.0001, "Angle 78.0° must have 0.0 progress")

        // Angles strictly below 78° must return progress > 0
        let belowAngles = [77.9, 70.0, 60.0, 50.0, 35.0, 26.0]
        for angle in belowAngles {
            let p = controller.computeProgress(for: angle)
            #expect(p > 0.0, "Angle \(angle)° (< 78°) must have progress > 0")
            #expect(p <= 1.0, "Progress must not exceed 1.0")
        }

        // Closed endpoint (25.0°) and below must return exactly 1.0
        let pAtEndpoint = controller.computeProgress(for: 25.0)
        #expect(abs(pAtEndpoint - 1.0) < 0.0001, "Closed endpoint 25.0° must have 1.0 progress")

        let pBelowEndpoint = controller.computeProgress(for: 15.0)
        #expect(abs(pBelowEndpoint - 1.0) < 0.0001, "Angle below endpoint must have 1.0 progress")
    }

    @Test("Progress monotonicity down to closed endpoint")
    @MainActor
    func testProgressMonotonicityDownToClosedEndpoint() {
        let controller = AnimationController()
        controller.settings.preset = .comfortable105
        controller.settings.closingTriggerAngle = 78.0
        controller.settings.closedEndpointAngle = 10.0

        var lastProgress: Double = -1.0
        for angleInt in stride(from: 78, through: 10, by: -1) {
            let angle = Double(angleInt)
            let p = controller.computeProgress(for: angle)
            #expect(p >= lastProgress, "Progress should monotonically increase as lid closes")
            #expect(p >= 0.0 && p <= 1.0, "Progress must remain normalized in [0, 1]")
            lastProgress = p
        }

        let pEnd = controller.computeProgress(for: 10.0)
        #expect(abs(pEnd - 1.0) < 0.0001)
    }

    @Test("Sensor high precision resolution")
    func testSensorHighPrecisionResolution() {
        let sensor = LidAngleSensor.shared
        let started = sensor.start(targetHz: 60.0)
        #expect(started)

        if let reading = sensor.readCurrentAngle() {
            #expect(reading.angle > 0.0 && reading.angle <= 180.0)
            #expect(reading.source == .highPrecision || reading.source == .standard)
        }
    }
}
