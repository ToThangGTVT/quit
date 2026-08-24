import SwiftUI
import ServiceManagement

/// Các lệnh của Task Manager, đưa vào menu bar chuẩn của macOS.
struct TaskManagerCommands: Commands {
    @Bindable var presenter: AppListPresenter
    @Bindable var router: AppRouter
    @Bindable var state: TaskManagerState

    var body: some Commands {
        // Thứ tự menu tự tạo: Tệp | Tùy chọn | Xem, giống Task Manager.
        CommandMenu(L.t("Tệp", "File")) {
            Button(L.t("Chạy tác vụ mới...", "Run new task...")) { router.runNewTask() }
                .keyboardShortcut("n")
            Divider()
            Button(L.t("Kết thúc tác vụ", "End task")) { endSelectedTask() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state.selectedPids.isEmpty)
        }

        CommandMenu(L.t("Tùy chọn", "Options")) {
            Button(L.t("Làm mới ngay", "Refresh now")) { presenter.refresh() }
                .keyboardShortcut("r")
            Picker(L.t("Tốc độ cập nhật", "Update speed"), selection: $presenter.updateSpeed) {
                ForEach(UpdateSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            Divider()
            Toggle(L.t("Luôn ở trên cùng", "Always on top"), isOn: $router.isAlwaysOnTop)
            Toggle(L.t("Mở khi đăng nhập", "Open at login"), isOn: launchAtLogin)
            Divider()
            Button(router.isCompact ? L.t("Thêm chi tiết", "More details") : L.t("Ít chi tiết hơn", "Fewer details")) {
                router.setCompact(!router.isCompact)
            }
            .keyboardShortcut("d")
            Divider()
            Picker(L.t("Ngôn ngữ", "Language"), selection: Bindable(L10n.shared).language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Divider()
            Button(L.t("Mở rộng tất cả nhóm", "Expand all groups")) { state.collapsedGroups.removeAll() }
                .disabled(state.tab != .processes)
            Button(L.t("Thu gọn tất cả nhóm", "Collapse all groups")) {
                state.collapsedGroups = Set(ProcessCategory.allCases.map { "\($0.rawValue)" })
            }
            .disabled(state.tab != .processes)
        }

        // Danh sách tab + tài nguyên hiệu suất nằm trong menu View chuẩn (⌘1...⌘7).
        CommandGroup(after: .sidebar) {
            ForEach(Array(TMTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { state.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Picker(L.t("Tài nguyên hiệu suất", "Performance resource"), selection: $state.perfResource) {
                ForEach(PerfResource.allCases) { resource in
                    Text(resource.title).tag(resource)
                }
            }
            .disabled(state.tab != .performance)
        }

        // Bỏ các menu chuẩn không dùng đến trong app này.
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .pasteboard) {}
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(replacing: .help) {}
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                if enabled { try? SMAppService.mainApp.register() }
                else { try? SMAppService.mainApp.unregister() }
            }
        )
    }

    private func endSelectedTask() {
        for pid in state.selectedPids {
            if let entity = presenter.rawEntities.first(where: { $0.id == pid }) {
                presenter.forceQuit(entity)
            }
        }
        state.clearSelectedPids()
    }
}
