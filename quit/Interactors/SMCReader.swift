import Foundation
import IOKit

/// Đọc cảm biến nhiệt độ và quạt qua AppleSMC.
///
/// Đây là cách duy nhất lấy được nhiệt độ/quạt trên máy Apple (không có sysctl
/// nào cho việc này). Mở AppleSMC và **đọc** không cần quyền root — chỉ ghi mới
/// cần. Danh sách khoá được liệt kê một lần lúc khởi động (máy này có 2051 khoá,
/// quét hết mỗi giây sẽ quá tốn), sau đó mỗi nhịp chỉ đọc các khoá đã chọn.
final class SMCReader {

    // MARK: - ABI của AppleSMC

    private struct Vers {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct Param {
        var key: UInt32 = 0
        var vers = Vers()
        var pLimit = PLimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 {
        case readBytes = 5
        case readIndex = 8
        case readKeyInfo = 9
    }

    // MARK: - Trạng thái

    private var connection: io_connect_t = 0
    private var isOpen = false
    private var didDiscover = false
    private var temperatureKeys: [(key: String, info: KeyInfo, group: SensorGroup)] = []
    private var fanKeys: [(index: Int, actual: (String, KeyInfo), min: (String, KeyInfo)?,
                           max: (String, KeyInfo)?, target: (String, KeyInfo)?)] = []

    deinit {
        if isOpen { IOServiceClose(connection) }
    }

    // MARK: - Công khai

    func read() -> SensorsInfo {
        guard openIfNeeded() else { return SensorsInfo() }
        discoverIfNeeded()

        var info = SensorsInfo()
        for sensor in temperatureKeys {
            guard let value = value(sensor.key, sensor.info), value > 5, value < 130 else { continue }
            info.temperatures.append(TemperatureSensor(id: sensor.key, group: sensor.group, value: value))
        }
        for fan in fanKeys {
            guard let rpm = value(fan.actual.0, fan.actual.1) else { continue }
            info.fans.append(FanInfo(
                id: fan.actual.0,
                index: fan.index,
                rpm: rpm,
                minRPM: fan.min.flatMap { value($0.0, $0.1) } ?? 0,
                maxRPM: fan.max.flatMap { value($0.0, $0.1) } ?? 0,
                target: fan.target.flatMap { value($0.0, $0.1) } ?? 0
            ))
        }
        return info
    }

    // MARK: - Kết nối

    private func openIfNeeded() -> Bool {
        if isOpen { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return false }
        isOpen = true
        return true
    }

    /// Liệt kê toàn bộ khoá một lần, giữ lại khoá nhiệt độ và quạt.
    private func discoverIfNeeded() {
        guard !didDiscover else { return }
        didDiscover = true

        guard let countInfo = keyInfo("#KEY"),
              let countValue = value("#KEY", countInfo) else { return }
        let total = Int(countValue)

        var fanCandidates: [String: KeyInfo] = [:]
        for index in 0..<total {
            var input = Param()
            input.data8 = Command.readIndex.rawValue
            input.data32 = UInt32(index)
            guard let output = call(&input) else { continue }
            let name = Self.string(from: output.key)
            guard name.hasPrefix("T") || name.hasPrefix("F") else { continue }
            guard let info = keyInfo(name) else { continue }

            if name.hasPrefix("F") {
                fanCandidates[name] = info
            } else if let group = Self.group(for: name) {
                temperatureKeys.append((name, info, group))
            }
        }

        let fanCount = Int(value("FNum", fanCandidates["FNum"] ?? KeyInfo()) ?? 0)
        for index in 0..<max(fanCount, 0) {
            let actual = "F\(index)Ac"
            guard let info = fanCandidates[actual] else { continue }
            fanKeys.append((
                index: index,
                actual: (actual, info),
                min: fanCandidates["F\(index)Mn"].map { ("F\(index)Mn", $0) },
                max: fanCandidates["F\(index)Mx"].map { ("F\(index)Mx", $0) },
                target: fanCandidates["F\(index)Tg"].map { ("F\(index)Tg", $0) }
            ))
        }
    }

    // MARK: - Đọc khoá

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input,
                                              MemoryLayout<Param>.stride, &output, &size)
        return result == kIOReturnSuccess ? output : nil
    }

    private func keyInfo(_ key: String) -> KeyInfo? {
        var input = Param()
        input.key = Self.code(from: key)
        input.data8 = Command.readKeyInfo.rawValue
        return call(&input)?.keyInfo
    }

    private func value(_ key: String, _ info: KeyInfo) -> Double? {
        guard info.dataSize > 0 else { return nil }
        var input = Param()
        input.key = Self.code(from: key)
        input.data8 = Command.readBytes.rawValue
        input.keyInfo = info
        guard let output = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return Self.decode(bytes, type: info.dataType)
    }

    // MARK: - Giải mã

    private static func decode(_ bytes: [UInt8], type: UInt32) -> Double? {
        switch string(from: type) {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "ui8 ", "ui16", "ui32":
            return bytes.reduce(0.0) { $0 * 256 + Double($1) }
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        default:
            return nil
        }
    }

    private static func code(from key: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in key.utf8.prefix(4) { value = (value << 8) | UInt32(byte) }
        return value
    }

    private static func string(from code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                     UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    /// Phân nhóm theo tiền tố khoá SMC của Apple Silicon.
    private static func group(for key: String) -> SensorGroup? {
        guard key.count == 4 else { return nil }
        let prefix = String(key.prefix(2))
        switch prefix {
        case "Tp": return .cpuPerformance
        case "Te": return .cpuEfficiency
        case "Tg": return .gpu
        case "Tm": return .memory
        case "TH", "TN": return .storage
        case "TB": return .battery
        case "Ts", "TW": return .enclosure
        case "TC", "TS": return .cpuOther
        case "Tc", "TP", "Tb": return .power
        default: return nil
        }
    }
}
