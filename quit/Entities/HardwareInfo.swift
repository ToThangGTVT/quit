import Foundation
import Darwin
import IOKit
import Metal

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

    // Tần số tối đa từng cụm lõi (IODeviceTree:/arm-io/pmgr → voltage-states)
    let performanceMaxGHz: Double
    let efficiencyMaxGHz: Double
    let performanceLevelName: String
    let efficiencyLevelName: String
    let l2Performance: UInt64
    let l2Efficiency: UInt64
    let cacheLineSize: UInt64
    let pageSize: UInt64
    let osVersion: String
    let targetType: String

    // Đĩa (IOBlockStorageDevice → Device Characteristics)
    let diskModel: String
    let diskMedium: String
    let diskRevision: String

    // GPU qua Metal
    let metalName: String
    let metalUnifiedMemory: Bool
    let metalWorkingSet: UInt64
    let metalMaxBuffer: UInt64
    let metalRaytracing: Bool

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

        performanceLevelName = HardwareInfo.string("hw.perflevel0.name") ?? "Performance"
        efficiencyLevelName = HardwareInfo.string("hw.perflevel1.name") ?? "Efficiency"
        l2Performance = HardwareInfo.number("hw.perflevel0.l2cachesize") ?? 0
        l2Efficiency = HardwareInfo.number("hw.perflevel1.l2cachesize") ?? 0
        cacheLineSize = HardwareInfo.number("hw.cachelinesize") ?? 0
        pageSize = HardwareInfo.number("hw.pagesize") ?? 0
        targetType = HardwareInfo.string("hw.targettype") ?? "—"
        let product = HardwareInfo.string("kern.osproductversion") ?? "?"
        let build = HardwareInfo.string("kern.osversion") ?? "?"
        osVersion = "macOS \(product) (\(build))"

        // voltage-states5 = cụm hiệu năng, voltage-states1 = cụm tiết kiệm điện
        performanceMaxGHz = HardwareInfo.maxFrequencyGHz(key: "voltage-states5-sram")
        efficiencyMaxGHz = HardwareInfo.maxFrequencyGHz(key: "voltage-states1-sram")

        let disk = HardwareInfo.readDiskCharacteristics()
        diskModel = disk.model
        diskMedium = disk.medium
        diskRevision = disk.revision

        if let device = MTLCreateSystemDefaultDevice() {
            metalName = device.name
            metalUnifiedMemory = device.hasUnifiedMemory
            metalWorkingSet = device.recommendedMaxWorkingSetSize
            metalMaxBuffer = UInt64(device.maxBufferLength)
            metalRaytracing = device.supportsRaytracing
        } else {
            metalName = "—"
            metalUnifiedMemory = false
            metalWorkingSet = 0
            metalMaxBuffer = 0
            metalRaytracing = false
        }

        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            bootTime = Date(timeIntervalSince1970: Double(tv.tv_sec))
        } else {
            bootTime = Date()
        }
    }

    var efficiencyCores: Int { coreClusters.filter { $0 == "E" }.count }

    /// Tần số cao nhất của một cụm lõi, đọc bảng voltage-states của pmgr.
    private static func maxFrequencyGHz(key: String) -> Double {
        let pmgr = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
        guard pmgr != 0 else { return 0 }
        defer { IOObjectRelease(pmgr) }
        guard let data = IORegistryEntryCreateCFProperty(pmgr, key as CFString,
                                                        kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data, data.count >= 8 else { return 0 }

        var maxHz: UInt32 = 0
        data.withUnsafeBytes { raw in
            for index in 0..<(data.count / 8) {
                let hz = raw.loadUnaligned(fromByteOffset: index * 8, as: UInt32.self)
                if hz > maxHz { maxHz = hz }
            }
        }
        return Double(maxHz) / 1_000_000_000.0
    }

    /// Model ổ đĩa hệ thống; bỏ qua disk image và khe thẻ nhớ.
    private static func readDiskCharacteristics() -> (model: String, medium: String, revision: String) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDevice"),
                                           &iterator) == KERN_SUCCESS else { return ("—", "—", "—") }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            guard let props = IORegistryEntryCreateCFProperty(entry, "Device Characteristics" as CFString,
                                                              kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let name = props["Product Name"] as? String else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Disk Image") || trimmed.contains("Reader") { continue }
            return (trimmed,
                    (props["Medium Type"] as? String) ?? "—",
                    ((props["Product Revision Level"] as? String) ?? "—").trimmingCharacters(in: .whitespaces))
        }
        return ("—", "—", "—")
    }
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
        if performanceMaxGHz > 0 { return String(format: "%.2f GHz", performanceMaxGHz) }
        return baseSpeedGHz > 0 ? String(format: "%.2f GHz", baseSpeedGHz) : "—"
    }

    var efficiencySpeedText: String {
        efficiencyMaxGHz > 0 ? String(format: "%.2f GHz", efficiencyMaxGHz) : "—"
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
