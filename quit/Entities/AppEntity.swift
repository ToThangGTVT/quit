import AppKit

struct AppEntity: Identifiable {
    let id: Int32
    let name: String
    let memory: Double   // MB
    let cpu: Double      // % (100 = 1 full core)
    let netRxKBs: Double // TCP download KB/s
    let netTxKBs: Double // TCP upload KB/s
    let isRegular: Bool
    let runningApp: NSRunningApplication

    var icon: NSImage? { runningApp.icon }
}
