import SwiftUI

struct SystemStats {
    // CPU
    var cpuUsage: Double = 0            // 0...100
    var cpuSystemUsage: Double = 0      // phần thuộc kernel (0...100)
    var perCore: [Double] = []          // mức dùng từng lõi logic (0...100)
    var efficiencyUsage: Double = 0     // trung bình cụm E
    var performanceUsage: Double = 0    // trung bình cụm P

    // Bộ nhớ
    var memoryUsagePercentage: Double = 0
    var memoryPressure: Int = 0
    var memTotal: UInt64 = 0
    var memUsed: UInt64 = 0
    var memAvailable: UInt64 = 0
    var memCached: UInt64 = 0
    var memCompressed: UInt64 = 0
    var memWired: UInt64 = 0
    var memApp: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0

    // Mạng
    var netRxKBs: Double = 0
    var netTxKBs: Double = 0
    var netTotalRx: UInt64 = 0          // tổng đã tải về từ lúc mở app
    var netTotalTx: UInt64 = 0

    // GPU
    var gpu = GPUInfo()

    // Đĩa
    var diskReadKBs: Double = 0
    var diskWriteKBs: Double = 0
    var diskActive: Double = 0          // % thời gian hoạt động

    // Đếm
    var processCount: Int = 0
    var threadCount: Int = 0
    var handleCount: Int = 0
    var uptime: TimeInterval = 0

    var netMbps: Double { (netRxKBs + netTxKBs) * 8.0 / 1000.0 }
    var diskKBs: Double { diskReadKBs + diskWriteKBs }

    var pressureText: String {
        if memoryPressure == 1 { return L.t("Thấp", "Low") }
        if memoryPressure == 2 { return L.t("Vừa", "Medium") }
        if memoryPressure == 4 { return L.t("Cao", "High") }
        if memoryUsagePercentage < 50 { return L.t("Thấp", "Low") }
        if memoryUsagePercentage < 80 { return L.t("Vừa", "Medium") }
        return L.t("Cao", "High")
    }

    var pressureColor: Color {
        if memoryPressure == 1 { return .green }
        if memoryPressure == 2 { return .orange }
        if memoryPressure == 4 { return .red }
        if memoryUsagePercentage < 50 { return .green }
        if memoryUsagePercentage < 80 { return .orange }
        return .red
    }

    var uptimeText: String {
        let total = Int(uptime)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d:%02d", d, h, m, s)
    }
}

/// Định dạng dung lượng theo kiểu Task Manager (GB/MB một chữ số thập phân).
enum Fmt {
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }

    static func mb(_ bytes: UInt64) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
    }

    static func bytesAuto(_ bytes: UInt64) -> String {
        let d = Double(bytes)
        if d >= 1_073_741_824 { return String(format: "%.1f GB", d / 1_073_741_824) }
        if d >= 1_048_576 { return String(format: "%.1f MB", d / 1_048_576) }
        if d >= 1024 { return String(format: "%.0f KB", d / 1024) }
        return "\(bytes) B"
    }

    /// Cột "Bộ nhớ" của Task Manager luôn hiển thị MB.
    static func memoryCell(_ mb: Double) -> String {
        if mb <= 0 { return "0 MB" }
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.1f MB", mb)
    }

    /// Cột "Đĩa": MB/s.
    static func diskCell(_ kbs: Double) -> String {
        if kbs < 0.05 { return "0 MB/s" }
        return String(format: "%.1f MB/s", kbs / 1024)
    }

    /// Cột "Mạng": Mbps.
    static func netCell(_ mbps: Double) -> String {
        if mbps < 0.05 { return "0 Mbps" }
        return String(format: "%.1f Mbps", mbps)
    }

    static func rate(_ kbs: Double) -> String {
        if kbs >= 1024 { return String(format: "%.1f MB/s", kbs / 1024) }
        return String(format: "%.0f KB/s", kbs)
    }

    static func bitrate(_ kbs: Double) -> String {
        let kbps = kbs * 8.0
        if kbps >= 1000 { return String(format: "%.1f Mbps", kbps / 1000) }
        return String(format: "%.0f Kbps", kbps)
    }

    static func cpuTime(_ seconds: Double) -> String {
        let t = Int(seconds)
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}
