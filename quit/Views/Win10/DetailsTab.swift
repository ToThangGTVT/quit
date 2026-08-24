import SwiftUI

struct DetailsTab: View {
    var presenter: AppListPresenter
    @Binding var selection: Set<Int32>
    @Binding var sortKey: String
    @Binding var ascending: Bool
    @State private var collapsed: Set<String> = []

    var body: some View {
        W10Grid(columns: columns,
                sections: [W10Section(id: "all", title: nil, rows: rows)],
                selection: $selection,
                sortKey: $sortKey,
                ascending: $ascending,
                collapsed: $collapsed,
                menuBuilder: { entity in AnyView(menu(for: entity)) })
    }

    private var rows: [AppEntity] {
        AppEntity.sorted(presenter.rawEntities,
                         key: ProcSortKey(rawValue: sortKey) ?? .name,
                         ascending: ascending)
    }

    /// Tab Chi tiết của Task Manager không tô màu ô, chỉ là bảng thuần.
    private var columns: [W10Column<AppEntity>] {
        [
            W10Column(id: "name", title: L.t("Tên", "Name"), width: nil, minWidth: 200, trailing: false,
                      content: { AnyView(NameCell(entity: $0)) }),
            W10Column(id: "pid", title: "PID", width: 58, text: { "\($0.id)" }),
            W10Column(id: "status", title: L.t("Trạng thái", "Status"), width: 84, trailing: false,
                      text: { $0.isSuspended ? L.t("Tạm ngưng", "Suspended") : L.t("Đang chạy", "Running") }),
            W10Column(id: "user", title: L.t("Tên người dùng", "User name"), width: 110, trailing: false,
                      text: { $0.user }),
            W10Column(id: "cpu", title: "CPU", width: 60, text: { ProcessesTab.percent($0.cpu) }),
            W10Column(id: "memory", title: L.t("Bộ nhớ", "Memory"), width: 88, text: { Fmt.memoryCell($0.memory) }),
            W10Column(id: "threads", title: L.t("Luồng", "Threads"), width: 58, text: { "\($0.threads)" }),
            W10Column(id: "handles", title: L.t("Bộ mô tả", "Handles"), width: 70, text: { "\($0.handles)" })
        ]
    }

    @ViewBuilder
    private func menu(for entity: AppEntity) -> some View {
        Button(L.t("Kết thúc tác vụ", "End task")) { presenter.forceQuit(entity) }
        Divider()
        Button(L.t("Đưa ra trước", "Bring to front")) { presenter.activate(entity) }
            .disabled(!entity.isGUIApp)
        Button(L.t("Mở vị trí tệp", "Open file location")) { presenter.revealInFinder(entity) }
            .disabled(entity.path.isEmpty)
    }
}
