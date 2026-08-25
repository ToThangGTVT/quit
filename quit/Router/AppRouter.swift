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
        win.setContentSize(isCompact ? Self.compactSize : Self.fullSize)
        win.contentMinSize = Self.minSize(compact: isCompact)
        self.window = win
        if let saved = savedFrame(compact: isCompact) {
            win.setFrame(saved, display: false)
        } else {
            win.center()
        }
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.level = isAlwaysOnTop ? .floating : .normal

        installToolbar(on: win)
        toolbarController?.setVisible(!isCompact)
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
        saveFrame()                 // chốt khung của chế độ sắp rời đi
        isCompact = compact
        toolbarController?.setVisible(!compact)
        guard let window else { return }
        window.contentMinSize = Self.minSize(compact: compact)

        let target: NSRect
        if let saved = savedFrame(compact: compact) {
            target = saved
        } else {
            // Lần đầu vào chế độ này: dùng kích thước mặc định, neo mép trên.
            let size = compact ? Self.compactSize : Self.fullSize
            var frame = window.frame
            let chrome = frame.height - window.contentLayoutRect.height
            frame.origin.y += frame.height - (size.height + chrome)
            frame.size = NSSize(width: size.width, height: size.height + chrome)
            target = frame
        }
        window.setFrame(target, display: true, animate: true)
    }

    // MARK: - Ghi nhớ khung cửa sổ

    /// Hai chế độ chênh nhau quá nhiều (1000×680 với 420×340) nên lưu riêng từng
    /// khoá. Dùng chung một khoá thì mỗi lần bật "Ít chi tiết hơn" sẽ ghi đè mất
    /// kích thước của chế độ đầy đủ.
    private static func frameKey(compact: Bool) -> String {
        compact ? "TaskManagerWindowFrameCompact" : "TaskManagerWindowFrame"
    }

    private static func minSize(compact: Bool) -> NSSize {
        compact ? NSSize(width: 320, height: 220) : NSSize(width: 780, height: 520)
    }

    private func saveFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame),
                                  forKey: Self.frameKey(compact: isCompact))
    }

    /// Khung đã lưu, chỉ trả về nếu nó còn nằm trên một màn hình đang cắm.
    private func savedFrame(compact: Bool) -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: Self.frameKey(compact: compact)) else {
            return nil
        }
        let frame = NSRectFromString(raw)
        guard frame.width > 0, frame.height > 0 else { return nil }
        // Rút màn phụ ra rồi mở lại app thì khung cũ nằm ngoài vùng nhìn thấy —
        // cửa sổ sẽ hiện ở chỗ không ai với tới được, nên bỏ qua và căn giữa.
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else {
            return nil
        }
        return frame
    }

    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }

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
        saveFrame()
        window = nil
        toolbarController = nil
        // Trở lại app chỉ-thanh-menu: không icon Dock, không menu bar.
        NSApp.setActivationPolicy(.accessory)
    }
}
