import XCTest
import Foundation
@testable import MacHinge
@testable import LidSensorKit

@MainActor
final class MacHingeTests: XCTestCase {

    func testProgressAtPreferredAngleIsExactlyZero() {
        let controller = AnimationController()
        controller.settings.preset = .angle105
        controller.settings.deadbandDegrees = 1.0

        let pPref = controller.computeProgress(for: 105.0)
        XCTAssertEqual(pPref, 0.0, accuracy: 0.0001)

        let pWithinDeadband = controller.computeProgress(for: 104.5)
        XCTAssertEqual(pWithinDeadband, 0.0, accuracy: 0.0001)
    }

    func testProgressMonotonicityDownToClosedEndpoint() {
        let controller = AnimationController()
        controller.settings.preset = .angle105
        controller.settings.deadbandDegrees = 1.0
        controller.settings.closedEndpointAngle = 10.0

        var lastProgress: Double = -1.0
        for angleInt in stride(from: 104, through: 10, by: -2) {
            let angle = Double(angleInt)
            let p = controller.computeProgress(for: angle)
            XCTAssertGreaterThanOrEqual(p, lastProgress, "Progress should monotonically increase as lid closes")
            XCTAssertTrue(p >= 0.0 && p <= 1.0, "Progress must remain normalized in [0, 1]")
            lastProgress = p
        }

        let pEnd = controller.computeProgress(for: 10.0)
        XCTAssertEqual(pEnd, 1.0, accuracy: 0.0001)
    }

    func testSensorHighPrecisionResolution() {
        let sensor = LidAngleSensor.shared
        let started = sensor.start(targetHz: 60.0)
        XCTAssertTrue(started)

        if let reading = sensor.readCurrentAngle() {
            XCTAssertTrue(reading.angle > 0.0 && reading.angle <= 180.0)
            XCTAssertTrue(reading.source == .highPrecision || reading.source == .standard)
        }
    }
}
