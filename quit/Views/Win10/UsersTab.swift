import SwiftUI

struct UsersTab: View {
    var presenter: AppListPresenter
    @Binding var selection: Set<Int32>
    @Binding var sortKey: String
    @Binding var ascending: Bool
    @State private var collapsed: Set<String> = []

    var body: some View {
        W10Grid(columns: columns,
                sections: sections,
                selection: $selection,
                sortKey: $sortKey,
                ascending: $ascending,
                collapsed: $collapsed,
                menuBuilder: { entity in
                    AnyView(Button(L.t("Kết thúc tác vụ", "End task")) { presenter.forceQuit(entity) })
                })
    }

    private var columns: [W10Column<AppEntity>] {
        let stats = presenter.systemStats
        return [
            W10Column(id: "name", title: L.t("Người dùng", "Users"), width: nil, minWidth: 220, trailing: false,
                      content: { AnyView(NameCell(entity: $0).padding(.leading, 16)) }),
            W10Column(id: "status", title: L.t("Trạng thái", "Status"), width: 84, trailing: false,
                      text: { $0.isSuspended ? L.t("Tạm ngưng", "Suspended") : "" }),
            W10Column(id: "cpu", title: "CPU",
                      top: String(format: "%.0f%%", stats.cpuUsage),
                      topHeat: W10.cpuHeat(stats.cpuUsage), width: 64,
                      heat: { W10.cpuHeat($0.cpu) }, text: { ProcessesTab.percent($0.cpu) }),
            W10Column(id: "memory", title: L.t("Bộ nhớ", "Memory"),
                      top: String(format: "%.0f%%", stats.memoryUsagePercentage),
                      topHeat: stats.memoryUsagePercentage / 100, width: 88,
                      heat: { W10.memoryHeat($0.memory, total: stats.memTotal) },
                      text: { Fmt.memoryCell($0.memory) }),
            W10Column(id: "disk", title: L.t("Đĩa", "Disk"),
                      top: String(format: "%.0f%%", stats.diskActive),
                      topHeat: stats.diskActive / 100, width: 88,
                      heat: { W10.diskHeat($0.diskKBs) }, text: { Fmt.diskCell($0.diskKBs) }),
            W10Column(id: "network", title: L.t("Mạng", "Network"), width: 88,
                      heat: { W10.netHeat($0.netMbps) }, text: { Fmt.netCell($0.netMbps) })
        ]
    }

    private var sections: [W10Section<AppEntity>] {
        let key = ProcSortKey(rawValue: sortKey) ?? .cpu
        let grouped = Dictionary(grouping: presenter.rawEntities.filter { !$0.user.isEmpty },
                                 by: { $0.user })
        let currentUser = NSUserName()
        return grouped.keys.sorted { lhs, rhs in
            if lhs == currentUser { return true }
            if rhs == currentUser { return false }
            return lhs < rhs
        }.map { user in
            let rows = AppEntity.sorted(grouped[user] ?? [], key: key, ascending: ascending)
            let cpu = rows.reduce(0) { $0 + $1.cpu }
            let memory = rows.reduce(0) { $0 + $1.memory }
            let disk = rows.reduce(0) { $0 + $1.diskKBs }
            let net = rows.reduce(0) { $0 + $1.netMbps }
            let title = user == currentUser ? "\(NSFullUserName()) (\(user))" : user
            return W10Section(
                id: user,
                title: L.t("\(title) — \(rows.count) tiến trình",
                           "\(title) — \(rows.count) processes"),
                rows: rows,
                summary: [
                    "cpu": ProcessesTab.percent(cpu),
                    "memory": Fmt.memoryCell(memory),
                    "disk": Fmt.diskCell(disk),
                    "network": Fmt.netCell(net)
                ]
            )
        }
    }
}
