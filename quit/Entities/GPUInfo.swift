import Foundation

/// Số liệu GPU đọc từ IOAccelerator (cùng nguồn mà Stats dùng).
struct GPUInfo {
    var name: String = "GPU"
    var coreCount: Int = 0
    var utilization: Double = 0        // Device Utilization %
    var renderer: Double = 0           // Renderer Utilization %
    var tiler: Double = 0              // Tiler Utilization %
    var inUseMemory: UInt64 = 0        // In use system memory
    var allocatedMemory: UInt64 = 0    // Alloc system memory
}

/// Một thiết bị Bluetooth.
struct BluetoothDeviceInfo: Identifiable {
    let id: String            // địa chỉ MAC
    let name: String
    let kind: String
    let connected: Bool
    let battery: Int?
    let batteryLeft: Int?
    let batteryRight: Int?
    let batteryCase: Int?
    let rssi: Int?

    var batteryText: String {
        var parts: [String] = []
        if let battery { parts.append("\(battery)%") }
        if let batteryLeft { parts.append(L.t("T", "L") + " \(batteryLeft)%") }
        if let batteryRight { parts.append(L.t("P", "R") + " \(batteryRight)%") }
        if let batteryCase { parts.append(L.t("Hộp", "Case") + " \(batteryCase)%") }
        return parts.isEmpty ? "—" : parts.joined(separator: "  ")
    }
}

struct BluetoothController {
    var address: String = "—"
    var chipset: String = "—"
    var firmware: String = "—"
    var transport: String = "—"
    var vendor: String = "—"
    var powered: Bool = false
}
