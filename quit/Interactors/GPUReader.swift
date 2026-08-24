import Foundation
import IOKit

/// Đọc GPU qua IORegistry: service lớp `IOAccelerator`, khoá `PerformanceStatistics`.
/// Đây cũng là nguồn số liệu của exelban/Stats (không dùng API riêng của Metal).
final class GPUReader {
    private(set) var name: String = "GPU"
    private(set) var coreCount: Int = 0

    func read() -> GPUInfo {
        var info = GPUInfo()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return info }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var raw: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = raw?.takeRetainedValue() as? [String: Any] {

                if let model = props["model"] as? Data,
                   let text = String(data: model, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0")), !text.isEmpty {
                    info.name = text
                }
                if let cores = props["gpu-core-count"] as? Int {
                    info.coreCount = cores
                } else if let cores = props["gpu-core-count"] as? NSNumber {
                    info.coreCount = cores.intValue
                }

                info.ioClass = props["IOClass"] as? String ?? ""

                if let agc = props["AGCInfo"] as? [String: Int], let off = agc["poweredOffByAGC"] {
                    info.poweredOn = off == 0
                }

                if let stats = props["PerformanceStatistics"] as? [String: Any] {
                    info.utilization = min(Self.double(stats["Device Utilization %"])
                        ?? Self.double(stats["GPU Activity(%)"]) ?? 0, 100)
                    info.renderer = min(Self.double(stats["Renderer Utilization %"]) ?? 0, 100)
                    info.tiler = min(Self.double(stats["Tiler Utilization %"]) ?? 0, 100)
                    info.temperature = Self.double(stats["Temperature(C)"])
                    info.fanSpeed = (stats["Fan Speed(%)"] as? NSNumber)?.intValue
                    info.coreClock = (stats["Core Clock(MHz)"] as? NSNumber)?.intValue
                    info.memoryClock = (stats["Memory Clock(MHz)"] as? NSNumber)?.intValue
                    info.inUseMemory = UInt64(Self.double(stats["In use system memory"]) ?? 0)
                    info.allocatedMemory = UInt64(Self.double(stats["Alloc system memory"]) ?? 0)
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        name = info.name
        coreCount = info.coreCount
        return info
    }

    /// Thời gian GPU tích luỹ (nanosecond) theo từng PID.
    ///
    /// Mỗi user client của IOAccelerator có `IOUserClientCreator` ("pid 170, WindowServer")
    /// và `AppUsage` = danh sách command queue kèm `accumulatedGPUTime`. Cộng lại rồi lấy
    /// delta theo thời gian là ra % GPU của tiến trình — không cần quyền root như
    /// `powermetrics --show-process-gpu`.
    func readProcessGPUTime() -> [Int32: UInt64] {
        var result: [Int32: UInt64] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        var accelerator = IOIteratorNext(iterator)
        while accelerator != 0 {
            var children: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS {
                var client = IOIteratorNext(children)
                while client != 0 {
                    var raw: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(client, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let props = raw?.takeRetainedValue() as? [String: Any],
                       let creator = props["IOUserClientCreator"] as? String,
                       let usage = props["AppUsage"] as? [[String: Any]],
                       let pid = Self.pid(fromCreator: creator) {
                        let total = usage.reduce(UInt64(0)) { sum, queue in
                            sum + (((queue["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0)
                        }
                        if total > 0 { result[pid, default: 0] += total }
                    }
                    IOObjectRelease(client)
                    client = IOIteratorNext(children)
                }
                IOObjectRelease(children)
            }
            IOObjectRelease(accelerator)
            accelerator = IOIteratorNext(iterator)
        }
        return result
    }

    /// "pid 170, WindowServer" -> 170
    private static func pid(fromCreator creator: String) -> Int32? {
        let parts = creator.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return Int32(parts[1].replacingOccurrences(of: ",", with: ""))
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
