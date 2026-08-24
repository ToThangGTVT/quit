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

                if let stats = props["PerformanceStatistics"] as? [String: Any] {
                    info.utilization = Self.double(stats["Device Utilization %"])
                        ?? Self.double(stats["GPU Activity(%)"]) ?? 0
                    info.renderer = Self.double(stats["Renderer Utilization %"]) ?? 0
                    info.tiler = Self.double(stats["Tiler Utilization %"]) ?? 0
                    info.inUseMemory = UInt64(Self.double(stats["In use system memory"]) ?? 0)
                    info.allocatedMemory = UInt64(Self.double(stats["Alloc system memory"]) ?? 0)
                    // Trên Apple Silicon "Device Utilization %" đôi khi là 0 trong khi
                    // renderer/tiler vẫn chạy — lấy giá trị lớn nhất cho sát thực tế.
                    info.utilization = max(info.utilization, max(info.renderer, info.tiler))
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        name = info.name
        coreCount = info.coreCount
        return info
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
