import Foundation
import IOKit
import IOKit.hid

/// Reads the MacBook lid angle over IOKit HID.
///
/// The sensor is undocumented: vendor 0x05AC, usage page 0x20 (Sensor), usage 0x8A
/// (Orientation). Two feature reports carry the angle, little-endian after the
/// report id byte:
///   report 7: four bytes, hundredths of a degree (preferred, finer resolution)
///   report 1: two bytes, whole degrees (fallback)
/// No permission is required. Present on the 2019 16-inch MacBook Pro and later,
/// MacBook Air M2 and later, and 14/16-inch MacBook Pro with M1 Pro or later.
/// Absent on the M1 MacBook Air and the 13-inch M1/M2 MacBook Pro.
final class LidAngleSensor {
    static let vendorID = 0x05AC
    static let usagePage = 0x20
    static let usage = 0x8A

    enum Resolution {
        case hundredths   // report 7
        case wholeDegrees // report 1

        var reportID: CFIndex { self == .hundredths ? 7 : 1 }
        var minimumLength: CFIndex { self == .hundredths ? 5 : 3 }
        var label: String { self == .hundredths ? "report 7 (0.01 deg)" : "report 1 (1 deg)" }
    }

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    let resolution: Resolution

    /// Returns nil when no lid angle sensor is present or it cannot be opened.
    init?() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDPrimaryUsagePageKey as String: Self.usagePage,
            kIOHIDPrimaryUsageKey as String: Self.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        guard let set = IOHIDManagerCopyDevices(manager) as NSSet?, let first = set.allObjects.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
        let device = first as! IOHIDDevice
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
        self.manager = manager
        self.device = device

        if Self.read(device, .hundredths) != nil {
            resolution = .hundredths
        } else if Self.read(device, .wholeDegrees) != nil {
            resolution = .wholeDegrees
        } else {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    static func isAvailable() -> Bool {
        LidAngleSensor() != nil
    }

    /// Current lid angle in degrees, 0 closed, or nil on a failed read.
    func readDegrees() -> Double? {
        Self.read(device, resolution)
    }

    private static func read(_ device: IOHIDDevice, _ resolution: Resolution) -> Double? {
        var buffer = [UInt8](repeating: 0, count: 8)
        var length: CFIndex = buffer.count
        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, resolution.reportID, ptr.baseAddress!, &length)
        }
        guard result == kIOReturnSuccess, length >= resolution.minimumLength else { return nil }
        let degrees: Double
        switch resolution {
        case .hundredths:
            let raw = UInt32(buffer[1]) | UInt32(buffer[2]) << 8 | UInt32(buffer[3]) << 16 | UInt32(buffer[4]) << 24
            degrees = Double(raw) / 100.0
        case .wholeDegrees:
            degrees = Double(UInt16(buffer[1]) | UInt16(buffer[2]) << 8)
        }
        guard degrees <= 360 else { return nil }
        return degrees
    }
}
