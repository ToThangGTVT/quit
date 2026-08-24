import AppKit
import Observation

/// Thanh tab dạng NSToolbar chuẩn macOS — trên macOS 26 các mục tự hiển thị
/// kiểu nút "glass" bo tròn kèm nhãn bên dưới, mục đang chọn được tô sáng.
final class TaskManagerToolbar: NSObject, NSToolbarDelegate {
    private let state: TaskManagerState
    private weak var toolbar: NSToolbar?

    init(state: TaskManagerState) {
        self.state = state
        super.init()
    }

    func install(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "TaskManagerToolbar")
        toolbar.delegate = self
        // Chỉ icon, không nhãn chữ — gọn hơn; tên tab xem ở tooltip và menu Xem (⌘1...⌘7).
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = Self.identifier(state.tab)

        window.toolbar = toolbar
        // Kiểu .preference = hàng tab icon + nhãn căn giữa (như cửa sổ Cài đặt của
        // macOS); gọn và rõ mục đang chọn hơn .unified vì không phải chen với tiêu đề.
        // Titlebar mỏng: tiêu đề bên trái, hàng icon dồn về bên phải.
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .visible
        self.toolbar = toolbar

        observeTab()
    }

    /// Nhãn/tooltip của NSToolbar không tự đổi theo ngôn ngữ, phải gán lại.
    func refreshLabels() {
        guard let toolbar else { return }
        for item in toolbar.items {
            guard let tab = TMTab(rawValue: item.itemIdentifier.rawValue) else { continue }
            item.label = tab.title
            item.paletteLabel = tab.title
            item.toolTip = tab.title
        }
    }

    func setVisible(_ visible: Bool) {
        toolbar?.isVisible = visible
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Chỉ một flexibleSpace ở đầu -> toàn bộ icon căn phải.
        [.flexibleSpace] + TMTab.allCases.map(Self.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        TMTab.allCases.map(Self.identifier)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = TMTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.toolTip = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)?
            .withSymbolConfiguration(Self.symbolConfig)
        item.isBordered = true
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    // MARK: - Đồng bộ

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = TMTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        state.tab = tab
    }

    /// Tab cũng đổi được từ menu bar (⌘1...⌘7) nên phải theo dõi ngược lại.
    private func observeTab() {
        withObservationTracking {
            _ = state.tab
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.toolbar?.selectedItemIdentifier = Self.identifier(self.state.tab)
                self.observeTab()
            }
        }
    }

    /// Cùng point size + weight cho mọi icon để không cái to cái nhỏ.
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        .applying(.init(scale: .medium))

    private static func identifier(_ tab: TMTab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(tab.rawValue)
    }
}
