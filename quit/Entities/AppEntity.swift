import AppKit

struct AppEntity: Identifiable {
    let id: Int32
    let name: String
    let memory: Double   // MB
    let cpu: Double      // % (100 = 1 full core)
    let isRegular: Bool
    let runningApp: NSRunningApplication

    var icon: NSImage? { runningApp.icon }
}
