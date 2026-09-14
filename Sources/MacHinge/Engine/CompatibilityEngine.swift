import Foundation
import IOKit
import IOKit.hid
import AppKit

public struct CompatibilityReport: Sendable {
    public let isCompatible: Bool
    public let macModel: String
    public let cpuArchitecture: String
    public let macOSVersion: String
    public let hasLidSensor: Bool
    public let hasHighPrecisionSensor: Bool
    public let hasBuiltinDisplay: Bool
    public let displayCount: Int
    public let unsupportedReason: String?

    public init(
        isCompatible: Bool,
        macModel: String,
        cpuArchitecture: String,
        macOSVersion: String,
        hasLidSensor: Bool,
        hasHighPrecisionSensor: Bool,
        hasBuiltinDisplay: Bool,
        displayCount: Int,
        unsupportedReason: String?
    ) {
        self.isCompatible = isCompatible
        self.macModel = macModel
        self.cpuArchitecture = cpuArchitecture
        self.macOSVersion = macOSVersion
        self.hasLidSensor = hasLidSensor
        self.hasHighPrecisionSensor = hasHighPrecisionSensor
        self.hasBuiltinDisplay = hasBuiltinDisplay
        self.displayCount = displayCount
        self.unsupportedReason = unsupportedReason
    }
}

public final class CompatibilityEngine: @unchecked Sendable {
    public static let shared = CompatibilityEngine()

    public init() {}

    public func evaluateCompatibility() -> CompatibilityReport {
        let model = getMacModel()
        let arch = getCPUArchitecture()
        let osVersion = getOSVersion()
        let (hasSensor, hasHighPrecision) = probeLidSensor()
        let (hasBuiltin, displayCount) = probeDisplays()

        var isCompatible = true
        var reason: String? = nil

        if !hasSensor {
            isCompatible = false
            if !hasBuiltin {
                reason = "MacHinge requires a MacBook with a built-in display and physical lid sensor. Desktop Macs (Mac Studio, Mac mini, Mac Pro, iMac) are not supported."
            } else {
                reason = "The Apple lid-angle HID sensor (Usage Page 0x0020, Usage 0x008A) was not detected on this Mac."
            }
        }

        return CompatibilityReport(
            isCompatible: isCompatible,
            macModel: model,
            cpuArchitecture: arch,
            macOSVersion: osVersion,
            hasLidSensor: hasSensor,
            hasHighPrecisionSensor: hasHighPrecision,
            hasBuiltinDisplay: hasBuiltin,
            displayCount: displayCount,
            unsupportedReason: reason
        )
    }

    private func getMacModel() -> String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return model.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return "Mac" }
            return String(cString: base)
        }
    }

    private func getCPUArchitecture() -> String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private func getOSVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    private func probeLidSensor() -> (hasSensor: Bool, hasHighPrecision: Bool) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDDeviceUsagePageKey as String: 0x0020,
            kIOHIDDeviceUsageKey as String: 0x008A
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let openRet = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openRet == kIOReturnSuccess else { return (false, false) }
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = devices.first else {
            return (false, false)
        }

        // Test High Precision Report ID 7
        var report7 = [UInt8](repeating: 0, count: 8)
        var len7 = report7.count
        let ret7 = IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, 7, &report7, &len7)
        let hasHighPrecision = (ret7 == kIOReturnSuccess && len7 >= 3)

        return (true, hasHighPrecision)
    }

    private func probeDisplays() -> (hasBuiltin: Bool, count: Int) {
        let screens = NSScreen.screens
        var hasBuiltin = false

        for screen in screens {
            if let screenNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if CGDisplayIsBuiltin(screenNum) != 0 {
                    hasBuiltin = true
                }
            }
        }
        return (hasBuiltin, screens.count)
    }
}
