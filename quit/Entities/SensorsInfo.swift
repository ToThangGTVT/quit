import Foundation

struct FanInfo: Identifiable {
    let id: String          // khoá SMC, ví dụ "F0Ac"
    let index: Int
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double
    let target: Double

    var name: String { L.t("Quạt \(index + 1)", "Fan \(index + 1)") }

    /// Vị trí trong khoảng min–max, để vẽ thanh mức.
    var percent: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max((rpm - minRPM) / (maxRPM - minRPM), 0), 1)
    }

    var rpmText: String { String(format: "%.0f RPM", rpm) }
}

enum SensorGroup: String, CaseIterable {
    case cpuPerformance, cpuEfficiency, cpuOther, gpu, memory, storage, battery, enclosure, power

    var title: String {
        switch self {
        case .cpuPerformance: return L.t("CPU – nhân P", "CPU – P cores")
        case .cpuEfficiency:  return L.t("CPU – nhân E", "CPU – E cores")
        case .cpuOther:       return L.t("CPU – khác", "CPU – other")
        case .gpu:            return "GPU"
        case .memory:         return L.t("Bộ nhớ", "Memory")
        case .storage:        return L.t("Ổ lưu trữ", "Storage")
        case .battery:        return L.t("Pin", "Battery")
        case .enclosure:      return L.t("Vỏ máy / tản nhiệt", "Enclosure / heatsink")
        case .power:          return L.t("Nguồn / sạc", "Power / charger")
        }
    }
}

struct TemperatureSensor: Identifiable {
    let id: String          // khoá SMC
    let group: SensorGroup
    let value: Double
}

struct SensorsInfo {
    var fans: [FanInfo] = []
    var temperatures: [TemperatureSensor] = []

    var available: Bool { !fans.isEmpty || !temperatures.isEmpty }

    func values(in group: SensorGroup) -> [Double] {
        temperatures.filter { $0.group == group }.map(\.value)
    }

    func average(_ group: SensorGroup) -> Double? {
        let list = values(in: group)
        return list.isEmpty ? nil : list.reduce(0, +) / Double(list.count)
    }

    func maximum(_ group: SensorGroup) -> Double? {
        values(in: group).max()
    }

    /// Nhiệt độ CPU tiêu biểu: cao nhất trong các nhân.
    var cpuTemperature: Double? {
        [maximum(.cpuPerformance), maximum(.cpuEfficiency), maximum(.cpuOther)]
            .compactMap { $0 }.max()
    }

    var gpuTemperature: Double? { maximum(.gpu) }
    var storageTemperature: Double? { maximum(.storage) }
    var batteryTemperature: Double? { maximum(.battery) }

    static func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f°C", value)
    }
}
