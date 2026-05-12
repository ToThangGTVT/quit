import AppKit

struct AppEntity: Identifiable {
    let id: Int32
    let name: String
    let memory: Double   // MB
    let cpu: Double      // % (100 = 1 full core)
    let netRxKBs: Double // TCP download KB/s
    let netTxKBs: Double // TCP upload KB/s
    let runningApp: NSRunningApplication?

    var isRegular: Bool { runningApp?.activationPolicy == .regular }
    var isGUIApp: Bool { runningApp != nil }
    var icon: NSImage? { runningApp?.icon }
}
