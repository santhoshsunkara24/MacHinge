import Foundation
import LidSensorKit

print("""
\u{001B}[1;36m========================================================================================
             MacBook High-Precision Lid / Hinge Angle HID Sensor (0.01° Resolution)
========================================================================================\u{001B}[0m
Hardware  : Apple Silicon SPU
HID Match : Vendor 0x05AC, UsagePage 0x0020, Usage 0x008A
Sensors   : Primary: Usage 0x0545 (Report ID 7, 0.01° resolution) | Fallback: Usage 0x047F (1.0°)

\u{001B}[1;33mMove your MacBook screen / lid physically to observe smooth 0.01° sub-degree tracking.\u{001B}[0m
Press \u{001B}[1mCtrl+C\u{001B}[0m to stop.
----------------------------------------------------------------------------------------
""")

let sensor = LidAngleSensor()

sensor.onReading = { reading in
    let sign = reading.deltaAngle >= 0 ? "+" : ""
    let deltaStr = String(format: "%@%5.2f°", sign, reading.deltaAngle)
    let velSign = reading.angularVelocity >= 0 ? "+" : ""
    let velStr = String(format: "%@%6.1f°/s", velSign, reading.angularVelocity)
    let hzStr = reading.frequencyHz > 0 ? String(format: "%5.1f Hz", reading.frequencyHz) : " --.- Hz"
    let timeStr = String(format: "%9.3f s", reading.timestamp)

    let barLength = 16
    let clampedAngle = max(0.0, min(140.0, reading.angleDegrees))
    let filledChars = Int((clampedAngle / 140.0) * Double(barLength))
    let bar = String(repeating: "█", count: filledChars) + String(repeating: "░", count: max(0, barLength - filledChars))

    let dir: String
    if abs(reading.deltaAngle) < 0.005 {
        dir = "  HOLD "
    } else if reading.deltaAngle > 0 {
        dir = "\u{001B}[32m▲ OPEN \u{001B}[0m"
    } else {
        dir = "\u{001B}[31m▼ CLOSE\u{001B}[0m"
    }

    let srcTag: String
    switch reading.source {
    case .highPrecision:
        srcTag = "\u{001B}[35m0.01° [0x0545]\u{001B}[0m"
    case .standard:
        srcTag = "\u{001B}[33m1.00° [0x047F]\u{001B}[0m"
    }

    print(String(format: "[%@] Angle: \u{001B}[1;32m%6.2f°\u{001B}[0m | [%@] | Δ: %7@ | Vel: %9@ | %@ | Src: %@ | Rate: %@",
                 timeStr, reading.angleDegrees, bar, deltaStr, velStr, dir, srcTag, hzStr))
    fflush(stdout)
}

if !sensor.start(targetHz: 60.0) {
    print("\u{001B}[31mError: Failed to connect to Apple HID lid sensor.\u{001B}[0m")
    exit(1)
}

// Signal handling
signal(SIGINT) { _ in
    print("\n\u{001B}[33mStopping lid sensor reader...\u{001B}[0m")
    exit(0)
}

RunLoop.main.run()
