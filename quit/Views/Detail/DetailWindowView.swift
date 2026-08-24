import SwiftUI

/// Cửa sổ chính: khung macOS (menu bar hệ thống + thanh tab segmented trong titlebar),
/// nội dung từng tab giữ nguyên giao diện Task Manager của Windows 10.
struct DetailWindowView: View {
    @Bindable var presenter: AppListPresenter
    @Bindable var router: AppRouter
    @Bindable var state: TaskManagerState

    @State private var procSort = ProcSortKey.memory.rawValue
    @State private var procAscending = false

    @State private var detailsSort = ProcSortKey.name.rawValue
    @State private var detailsAscending = true

    @State private var usersSort = ProcSortKey.cpu.rawValue
    @State private var usersAscending = false

    @State private var historySort = "cpuTime"
    @State private var historyAscending = false

    @State private var startupSort = "name"
    @State private var startupAscending = true

    @State private var servicesSort = "name"
    @State private var servicesAscending = true

    @State private var startupItems: [StartupItem] = []
    @State private var services: [ServiceItem] = []

    private let startupInteractor = StartupInteractor()

    var body: some View {
        Group {
            if router.isCompact {
                compactBody
            } else {
                fullBody
            }
        }
        .background(W10.content)
        .environment(\.colorScheme, .light)
        .onAppear { loadTabData() }
        .onChange(of: state.tab) { loadTabData() }
    }

    // MARK: - Toàn phần

    private var fullBody: some View {
        VStack(spacing: 0) {
            contentHeader
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            W10Footer(compactTitle: L.t("Ít chi tiết hơn", "Fewer details"),
                      compactSymbol: "chevron.up",
                      onCompact: { router.setCompact(true) },
                      actionTitle: footerTitle,
                      actionEnabled: footerEnabled,
                      action: footerAction)
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    /// Toolbar chỉ còn icon nên tên tab hiện ngay đầu vùng nội dung,
    /// kèm thông tin phụ của từng tab ở bên phải.
    private var contentHeader: some View {
        HStack(spacing: 12) {
            Text(state.tab.title)
                .font(W10.font(15, .semibold))
                .foregroundColor(W10.text)
            Spacer(minLength: 8)
            if let trailing = headerTrailing {
                Text(trailing)
                    .font(W10.font(11))
                    .foregroundColor(W10.textDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(W10.content)
        .overlay(alignment: .bottom) { Rectangle().fill(W10.gridLine).frame(height: 1) }
    }

    private var headerTrailing: String? {
        switch state.tab {
        case .processes:
            let count = presenter.rawEntities.count
            return L.t("\(count) tiến trình đang chạy", "\(count) processes running")
        case .appHistory:
            let since = Self.bootText(withSeconds: false)
            return L.t("Mức sử dụng tài nguyên từ \(since)", "Resource usage since \(since)")
        case .startup:
            let boot = Self.bootText(withSeconds: true)
            return L.t("Thời gian khởi động lần cuối: \(boot)", "Last boot time: \(boot)")
        case .users:
            return NSFullUserName()
        case .services:
            guard !services.isEmpty else { return nil }
            return L.t("\(services.count) dịch vụ", "\(services.count) services")
        case .details, .performance:
            return nil
        }
    }

    private static func bootText(withSeconds: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = withSeconds ? "dd/MM/yyyy HH:mm:ss" : "dd/MM/yyyy HH:mm"
        return formatter.string(from: HardwareInfo.current.bootTime)
    }

    @ViewBuilder
    private var content: some View {
        switch state.tab {
        case .processes:
            ProcessesTab(presenter: presenter,
                         selection: $state.procSelection,
                         sortKey: $procSort,
                         ascending: $procAscending,
                         collapsed: $state.collapsedGroups,
                         onShowDetails: { pid in
                             state.detailsSelection = [pid]
                             state.tab = .details
                         })
        case .performance:
            PerformanceTab(presenter: presenter, state: state)
        case .appHistory:
            AppHistoryTab(presenter: presenter,
                          sortKey: $historySort,
                          ascending: $historyAscending)
        case .startup:
            StartupTab(selection: $state.startupSelection,
                       sortKey: $startupSort,
                       ascending: $startupAscending,
                       items: startupItems)
        case .users:
            UsersTab(presenter: presenter,
                     selection: $state.usersSelection,
                     sortKey: $usersSort,
                     ascending: $usersAscending)
        case .details:
            DetailsTab(presenter: presenter,
                       selection: $state.detailsSelection,
                       sortKey: $detailsSort,
                       ascending: $detailsAscending)
        case .services:
            ServicesTab(selection: $state.servicesSelection,
                        sortKey: $servicesSort,
                        ascending: $servicesAscending,
                        items: services)
        }
    }

    // MARK: - Chân cửa sổ

    private var footerTitle: String {
        switch state.tab {
        case .processes, .details, .users: return L.t("Kết thúc tác vụ", "End task")
        case .appHistory:                  return L.t("Xóa lịch sử sử dụng", "Delete usage history")
        case .startup:                     return L.t("Mở vị trí tệp", "Open file location")
        case .services:                    return L.t("Tải lại danh sách", "Reload list")
        case .performance:                 return L.t("Làm mới ngay", "Refresh now")
        }
    }

    private var footerEnabled: Bool {
        switch state.tab {
        case .processes: return !state.procSelection.isEmpty
        case .details:   return !state.detailsSelection.isEmpty
        case .users:     return !state.usersSelection.isEmpty
        case .startup:   return !state.startupSelection.isEmpty
        default:         return true
        }
    }

    private func footerAction() {
        switch state.tab {
        case .processes: endTasks(state.procSelection); state.procSelection.removeAll()
        case .details:   endTasks(state.detailsSelection); state.detailsSelection.removeAll()
        case .users:     endTasks(state.usersSelection); state.usersSelection.removeAll()
        case .appHistory: presenter.clearUsageHistory()
        case .startup:
            if let id = state.startupSelection.first,
               let item = startupItems.first(where: { $0.id == id }) {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            }
        case .services:  loadServices()
        case .performance: presenter.refresh()
        }
    }

    private func endTasks(_ pids: Set<Int32>) {
        for pid in pids {
            if let entity = presenter.rawEntities.first(where: { $0.id == pid }) {
                presenter.forceQuit(entity)
            }
        }
    }

    // MARK: - Chế độ gọn

    private var compactBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(presenter.entities(in: .app)
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { entity in
                        HStack(spacing: 6) {
                            if let icon = entity.icon {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(entity.name).font(W10.font())
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(state.procSelection.contains(entity.id) ? W10.selection : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { state.procSelection = [entity.id] }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(W10.content)
            W10Footer(compactTitle: L.t("Thêm chi tiết", "More details"),
                      compactSymbol: "chevron.down",
                      onCompact: { router.setCompact(false) },
                      actionTitle: L.t("Kết thúc tác vụ", "End task"),
                      actionEnabled: !state.procSelection.isEmpty,
                      action: { endTasks(state.procSelection); state.procSelection.removeAll() })
        }
    }

    // MARK: - Nạp dữ liệu theo tab

    private func loadTabData() {
        switch state.tab {
        case .startup where startupItems.isEmpty:
            DispatchQueue.global(qos: .userInitiated).async {
                let items = startupInteractor.loadStartupItems()
                DispatchQueue.main.async { startupItems = items }
            }
        case .services where services.isEmpty:
            loadServices()
        default:
            break
        }
    }

    private func loadServices() {
        DispatchQueue.global(qos: .userInitiated).async {
            let items = startupInteractor.loadServices()
            DispatchQueue.main.async { services = items }
        }
    }
}
