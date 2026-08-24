import Foundation

/// Đọc Bluetooth qua `system_profiler SPBluetoothDataType -json`.
///
/// Không gọi thẳng IOBluetooth: trên macOS hiện tại việc đó chạm TCC và làm
/// **crash** tiến trình nếu app chưa khai báo quyền Bluetooth. system_profiler
/// là tiến trình riêng của Apple nên lấy được cùng dữ liệu mà không cần quyền.
final class BluetoothReader {

    func read() -> (controller: BluetoothController, devices: [BluetoothDeviceInfo]) {
        var controller = BluetoothController()
        var devices: [BluetoothDeviceInfo] = []

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return (controller, devices) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["SPBluetoothDataType"] as? [[String: Any]],
              let entry = list.first else { return (controller, devices) }

        if let props = entry["controller_properties"] as? [String: Any] {
            controller.address = props["controller_address"] as? String ?? "—"
            controller.chipset = props["controller_chipset"] as? String ?? "—"
            controller.firmware = props["controller_firmwareVersion"] as? String ?? "—"
            controller.transport = props["controller_transport"] as? String ?? "—"
            controller.vendor = props["controller_vendorID"] as? String ?? "—"
            controller.powered = (props["controller_state"] as? String) == "attrib_on"
        }

        devices += Self.parse(entry["device_connected"], connected: true)
        devices += Self.parse(entry["device_not_connected"], connected: false)
        return (controller, devices.sorted { lhs, rhs in
            lhs.connected == rhs.connected
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.connected
        })
    }

    private static func parse(_ value: Any?, connected: Bool) -> [BluetoothDeviceInfo] {
        guard let entries = value as? [[String: Any]] else { return [] }
        var result: [BluetoothDeviceInfo] = []
        for entry in entries {
            for (name, raw) in entry {
                guard let fields = raw as? [String: Any] else { continue }
                result.append(BluetoothDeviceInfo(
                    id: fields["device_address"] as? String ?? name,
                    name: name,
                    kind: fields["device_minorType"] as? String
                        ?? fields["device_majorType"] as? String ?? "—",
                    connected: connected,
                    battery: percent(fields["device_batteryLevelMain"]),
                    batteryLeft: percent(fields["device_batteryLevelLeft"]),
                    batteryRight: percent(fields["device_batteryLevelRight"]),
                    batteryCase: percent(fields["device_batteryLevelCase"]),
                    rssi: Int(fields["device_rssi"] as? String ?? "")
                ))
            }
        }
        return result
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return (value as? NSNumber)?.intValue }
        return Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }
}
