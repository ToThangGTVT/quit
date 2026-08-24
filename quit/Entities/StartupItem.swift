import Foundation

/// Một mục trong tab "Khởi động".
struct StartupItem: Identifiable {
    let id: String        // label
    let name: String
    let publisher: String
    let enabled: Bool
    let scope: String     // Người dùng / Hệ thống
    let path: String

    var statusText: String { enabled ? L.t("Đã bật", "Enabled") : L.t("Đã tắt", "Disabled") }
    var impactText: String { enabled ? L.t("Chưa đo được", "Not measured") : L.t("Không", "None") }
}

/// Một mục trong tab "Dịch vụ".
struct ServiceItem: Identifiable {
    let id: String        // label
    let pid: Int32        // 0 = đã dừng
    let status: Int32
    let scope: String

    var running: Bool { pid > 0 }
    var pidText: String { pid > 0 ? "\(pid)" : "" }
    var statusText: String { running ? L.t("Đang chạy", "Running") : L.t("Đã dừng", "Stopped") }
    var description: String {
        id.hasPrefix("com.apple.") ? L.t("Dịch vụ hệ thống Apple", "Apple system service") : L.t("Dịch vụ của bên thứ ba", "Third-party service")
    }
}
