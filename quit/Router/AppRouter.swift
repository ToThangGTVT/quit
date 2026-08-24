import AppKit
import SwiftUI
import Observation

@Observable
class AppRouter: NSObject, NSWindowDelegate {
    var isAlwaysOnTop: Bool = true {
        didSet { window?.level = isAlwaysOnTop ? .floating : .normal }
    }

    /// Chế độ "Ít chi tiết hơn" của Task Manager.
    var isCompact: Bool = false

    let state = TaskManagerState()

    private var window: NSWindow?
    private var toolbarController: TaskManagerToolbar?

    private static let fullSize = NSSize(width: 1000, height: 680)
    private static let compactSize = NSSize(width: 420, height: 340)

    func openDetailWindow(presenter: AppListPresenter) {
        // Menu bar chỉ hiện khi app là ứng dụng "thường"; ở chế độ accessory
        // (chỉ có icon thanh menu) macOS không vẽ menu bar cho app.
        NSApp.setActivationPolicy(.regular)

        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.fullSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L.t("Trình quản lý Tác vụ", "Task Manager")
        win.appearance = NSAppearance(named: .aqua)
        win.contentViewController = NSHostingController(
            rootView: DetailWindowView(presenter: presenter, router: self, state: state)
        )
        win.setContentSize(Self.fullSize)
        win.contentMinSize = NSSize(width: 780, height: 520)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.level = isAlwaysOnTop ? .floating : .normal
        self.window = win

        installToolbar(on: win)
        observeLanguage()

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Thanh tab: NSToolbar chuẩn macOS (macOS 26 tự vẽ kiểu nút bo tròn có nhãn).
    private func installToolbar(on win: NSWindow) {
        let controller = TaskManagerToolbar(state: state)
        controller.install(on: win)
        toolbarController = controller
    }

    /// Tiêu đề cửa sổ và nhãn toolbar là AppKit nên phải tự cập nhật khi đổi ngôn ngữ.
    private func observeLanguage() {
        withObservationTracking {
            _ = L10n.shared.language
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.window?.title = L.t("Trình quản lý Tác vụ", "Task Manager")
                self.toolbarController?.refreshLabels()
                self.observeLanguage()
            }
        }
    }

    func setCompact(_ compact: Bool) {
        isCompact = compact
        toolbarController?.setVisible(!compact)
        guard let window else { return }
        let size = compact ? Self.compactSize : Self.fullSize
        var frame = window.frame
        let chrome = window.frame.height - window.contentLayoutRect.height
        frame.origin.y += frame.height - (size.height + chrome)
        frame.size = NSSize(width: size.width, height: size.height + chrome)
        window.contentMinSize = compact ? NSSize(width: 320, height: 220)
                                       : NSSize(width: 780, height: 520)
        window.setFrame(frame, display: true, animate: true)
    }

    /// Tương đương "Chạy tác vụ mới" trong menu Tệp của Task Manager.
    func runNewTask() {
        let alert = NSAlert()
        alert.messageText = L.t("Tạo tác vụ mới", "Create new task")
        alert.informativeText = L.t("Nhập tên ứng dụng hoặc lệnh cần chạy.", "Enter an app name or command to run.")
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Safari, Terminal, /bin/ls..."
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L.t("Hủy", "Cancel"))
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", input]
        open.standardError = Pipe()
        do {
            try open.run()
            open.waitUntilExit()
        } catch {
            return
        }
        guard open.terminationStatus != 0 else { return }

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", input]
        try? shell.run()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        toolbarController = nil
        // Trở lại app chỉ-thanh-menu: không icon Dock, không menu bar.
        NSApp.setActivationPolicy(.accessory)
    }
}
