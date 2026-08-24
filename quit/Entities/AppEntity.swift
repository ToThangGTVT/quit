import AppKit

/// Nhóm tiến trình, tương ứng 3 nhóm của Task Manager Windows 10:
/// Apps / Background processes / Windows processes.
enum ProcessCategory: Int, CaseIterable {
    case app = 0
    case background = 1
    case system = 2

    var title: String {
        switch self {
        case .app:        return L.t("Ứng dụng", "Apps")
        case .background: return L.t("Tiến trình nền", "Background processes")
        case .system:     return L.t("Tiến trình hệ thống", "System processes")
        }
    }
}

struct AppEntity: Identifiable {
    let id: Int32
    let ppid: Int32
    let name: String
    let path: String
    let memory: Double        // MB
    let cpu: Double           // % toàn máy (100 = full tất cả lõi)
    let netRxKBs: Double      // KB/s
    let netTxKBs: Double      // KB/s
    let diskReadKBs: Double   // KB/s
    let diskWriteKBs: Double  // KB/s
    let threads: Int
    let handles: Int
    let cpuTime: Double       // giây, tích lũy từ lúc tiến trình chạy
    let netTotalBytes: UInt64 // byte, tích lũy
    let category: ProcessCategory
    let user: String
    let runningApp: NSRunningApplication?

    var diskKBs: Double { diskReadKBs + diskWriteKBs }
    var netMbps: Double { (netRxKBs + netTxKBs) * 8.0 / 1000.0 }

    var isRegular: Bool { runningApp?.activationPolicy == .regular }
    var isGUIApp: Bool { runningApp != nil }
    var icon: NSImage? { runningApp?.icon }

    /// Windows hiển thị lá xanh "Suspended"; trên macOS ứng dụng bị ẩn/App Nap là tương đương gần nhất.
    var isSuspended: Bool { (runningApp?.isHidden ?? false) && cpu < 0.1 }

    var statusText: String { isSuspended ? L.t("Tạm ngưng", "Suspended") : "" }

    static func categorize(path: String, app: NSRunningApplication?) -> ProcessCategory {
        if let app, app.activationPolicy == .regular { return .app }
        let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/var/db/"]
        if systemPrefixes.contains(where: { path.hasPrefix($0) }) { return .system }
        if path.isEmpty { return .system }
        return .background
    }
}
