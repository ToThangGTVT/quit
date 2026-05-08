import AppKit
import SwiftUI
import Observation

@Observable
class AppRouter: NSObject, NSWindowDelegate {
    var isAlwaysOnTop: Bool = true {
        didSet { window?.level = isAlwaysOnTop ? .floating : .normal }
    }
    private var window: NSWindow?

    func openDetailWindow(presenter: AppListPresenter) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Ứng dụng đang chạy"
        win.contentViewController = NSHostingController(
            rootView: DetailWindowView(presenter: presenter, router: self)
        )
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.level = .floating
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}
