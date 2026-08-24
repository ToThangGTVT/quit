import Foundation
import Darwin
import IOKit

/// Thông tin phần cứng tĩnh, hiển thị ở cột phải của tab Hiệu suất.
struct HardwareInfo {
    let cpuName: String
    let machineModel: String
    let physicalCores: Int
    let logicalCores: Int
    let sockets: Int
    let baseSpeedGHz: Double
    let l1: UInt64
    let l2: UInt64
    let l3: UInt64
    let memTotal: UInt64
    let memSlots: Int
    let diskName: String
    let diskCapacity: UInt64
    let bootTime: Date
    /// "E"/"P" theo đúng thứ tự lõi logic, đọc từ IODeviceTree:/cpus.
    let coreClusters: [String]
    let gpuName: String
    let gpuCores: Int

    static let current = HardwareInfo()

    private init() {
        cpuName = HardwareInfo.string("machdep.cpu.brand_string")
            ?? HardwareInfo.string("hw.model")
            ?? "CPU"
        machineModel = HardwareInfo.string("hw.model") ?? "Mac"
        physicalCores = Int(HardwareInfo.number("hw.physicalcpu") ?? 0)
        logicalCores = Int(HardwareInfo.number("hw.logicalcpu") ?? 0)
        sockets = Int(HardwareInfo.number("hw.packages") ?? 1)
        let hz = HardwareInfo.number("hw.cpufrequency_max") ?? HardwareInfo.number("hw.cpufrequency") ?? 0
        baseSpeedGHz = Double(hz) / 1_000_000_000.0
        l1 = (HardwareInfo.number("hw.l1dcachesize") ?? 0) + (HardwareInfo.number("hw.l1icachesize") ?? 0)
        l2 = HardwareInfo.number("hw.l2cachesize") ?? 0
        l3 = HardwareInfo.number("hw.l3cachesize") ?? 0
        memTotal = HardwareInfo.number("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory
        memSlots = 0

        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey])
        diskName = values?.volumeName ?? "Macintosh HD"
        diskCapacity = UInt64(values?.volumeTotalCapacity ?? 0)

        coreClusters = HardwareInfo.readCoreClusters()
        let gpu = GPUReader().read()
        // GPUReader không được chạm HardwareInfo.current (đang trong dispatch_once).
        gpuName = gpu.name == "GPU" ? cpuName : gpu.name
        gpuCores = gpu.coreCount

        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            bootTime = Date(timeIntervalSince1970: Double(tv.tv_sec))
        } else {
            bootTime = Date()
        }
    }

    var efficiencyCores: Int { coreClusters.filter { $0 == "E" }.count }
    var performanceCores: Int { coreClusters.filter { $0 == "P" }.count }

    /// Đọc kiểu cụm của từng lõi (icestorm = E, firestorm = P...) theo đúng
    /// thứ tự mà `host_processor_info` trả về.
    private static func readCoreClusters() -> [String] {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(root, "IODeviceTree", &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [String] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var raw: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = raw?.takeRetainedValue() as? [String: Any],
               let data = props["cluster-type"] as? Data,
               let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) {
                result.append(text)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return result
    }

    var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    var baseSpeedText: String {
        baseSpeedGHz > 0 ? String(format: "%.2f GHz", baseSpeedGHz) : "—"
    }

    static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buf, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buf)
        return value.isEmpty ? nil : value
    }

    static func number(_ key: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname(key, &value, &size, nil, 0) == 0, size == MemoryLayout<UInt64>.size {
            return value
        }
        var value32: UInt32 = 0
        var size32 = MemoryLayout<UInt32>.size
        if sysctlbyname(key, &value32, &size32, nil, 0) == 0 {
            return UInt64(value32)
        }
        return nil
    }
}
