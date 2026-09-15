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

    @Test("Effect start angle threshold is relative to preferred angle (preferred - 18°)")
    @MainActor
    func testEffectStartAngleRelativeToPreferredAngle() {
        let controller = AnimationController()
        controller.settings.closedEndpointAngle = 25.0

        // Test with 105° preset (Effect start = 105° - 18° = 87°)
        controller.settings.preset = .comfortable105
        #expect(controller.settings.effectivePreferredAngle == 105.0)
        #expect(controller.settings.effectStartAngle == 87.0)

        // Angles strictly above 87° must return exactly 0 progress
        let above87 = [120.0, 105.0, 104.5, 100.0, 90.0, 87.1]
        for angle in above87 {
            let p = controller.computeProgress(for: angle)
            #expect(abs(p - 0.0) < 0.0001, "Angle \(angle)° (> 87°) must have 0.0 progress for 105° preset")
        }

        // Exactly 87.0° must return exactly 0 progress
        let pAt87 = controller.computeProgress(for: 87.0)
        #expect(abs(pAt87 - 0.0) < 0.0001, "Angle 87.0° must have 0.0 progress for 105° preset")

        // Angles strictly below 87° must return progress > 0
        let below87 = [86.9, 80.0, 70.0, 60.0, 50.0, 35.0, 26.0]
        for angle in below87 {
            let p = controller.computeProgress(for: angle)
            #expect(p > 0.0, "Angle \(angle)° (< 87°) must have progress > 0")
            #expect(p <= 1.0, "Progress must not exceed 1.0")
        }

        // Closed endpoint (25.0°) and below must return exactly 1.0
        let pAtEndpoint = controller.computeProgress(for: 25.0)
        #expect(abs(pAtEndpoint - 1.0) < 0.0001, "Closed endpoint 25.0° must have 1.0 progress")

        // Test with 90° preset (Effect start = 90° - 18° = 72°)
        controller.settings.preset = .upright90
        #expect(controller.settings.effectivePreferredAngle == 90.0)
        #expect(controller.settings.effectStartAngle == 72.0)

        #expect(abs(controller.computeProgress(for: 80.0) - 0.0) < 0.0001)
        #expect(abs(controller.computeProgress(for: 72.0) - 0.0) < 0.0001)
        #expect(controller.computeProgress(for: 71.9) > 0.0)

        // Test with Custom 100° angle (Effect start = 100° - 18° = 82°)
        controller.settings.preset = .custom
        controller.settings.customPreferredAngle = 100.0
        #expect(controller.settings.effectivePreferredAngle == 100.0)
        #expect(controller.settings.effectStartAngle == 82.0)

        #expect(abs(controller.computeProgress(for: 85.0) - 0.0) < 0.0001)
        #expect(abs(controller.computeProgress(for: 82.0) - 0.0) < 0.0001)
        #expect(controller.computeProgress(for: 81.9) > 0.0)
    }

    @Test("Progress monotonicity down to closed endpoint")
    @MainActor
    func testProgressMonotonicityDownToClosedEndpoint() {
        let controller = AnimationController()
        controller.settings.preset = .comfortable105
        controller.settings.closedEndpointAngle = 10.0

        // Preferred = 105°, effect start = 87°
        var lastProgress: Double = -1.0
        for angleInt in stride(from: 87, through: 10, by: -1) {
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
