import SwiftUI

struct ProcessesTab: View {
    var presenter: AppListPresenter
    @Binding var selection: Set<Int32>
    @Binding var sortKey: String
    @Binding var ascending: Bool
    @Binding var collapsed: Set<String>
    let onShowDetails: (Int32) -> Void

    var body: some View {
        W10Grid(columns: columns,
                sections: sections,
                selection: $selection,
                sortKey: $sortKey,
                ascending: $ascending,
                collapsed: $collapsed,
                children: { presenter.tree.childrenByRoot[$0.id].map { children in
                    AppEntity.sorted(children,
                                     key: ProcSortKey(rawValue: sortKey) ?? .memory,
                                     ascending: ascending)
                } ?? [] },
                onDoubleClick: { entity in onShowDetails(entity.id) },
                menuBuilder: { entity in AnyView(menu(for: entity)) })
    }

    // MARK: - Cột

    private var columns: [W10Column<AppEntity>] {
        let stats = presenter.systemStats
        let netPercent = min(stats.netMbps / max(presenter.netScaleMbps, 0.1), 1)
        return [
            W10Column(
                id: "name", title: L.t("Tên", "Name"),
                width: nil, minWidth: 220, trailing: false,
                content: { entity in AnyView(NameCell(entity: entity)) }
            ),
            W10Column(
                id: "status", title: L.t("Trạng thái", "Status"),
                width: 72, trailing: false,
                content: { entity in AnyView(StatusCell(entity: entity)) }
            ),
            W10Column(
                id: "cpu", title: "CPU",
                top: String(format: "%.0f%%", stats.cpuUsage),
                topHeat: W10.cpuHeat(stats.cpuUsage),
                width: 64,
                heat: { W10.cpuHeat($0.cpu) },
                text: { Self.percent($0.cpu) }
            ),
            W10Column(
                id: "memory", title: L.t("Bộ nhớ", "Memory"),
                top: String(format: "%.0f%%", stats.memoryUsagePercentage),
                topHeat: stats.memoryUsagePercentage / 100,
                width: 88,
                heat: { W10.memoryHeat($0.memory, total: stats.memTotal) },
                text: { Fmt.memoryCell($0.memory) }
            ),
            W10Column(
                id: "disk", title: L.t("Đĩa", "Disk"),
                top: String(format: "%.0f%%", stats.diskActive),
                topHeat: stats.diskActive / 100,
                width: 88,
                heat: { W10.diskHeat($0.diskKBs) },
                text: { Fmt.diskCell($0.diskKBs) }
            ),
            W10Column(
                id: "gpu", title: "GPU",
                top: String(format: "%.0f%%", stats.gpu.utilization),
                topHeat: stats.gpu.utilization / 100,
                width: 64,
                heat: { W10.cpuHeat($0.gpu) },
                text: { Self.percent($0.gpu) }
            ),
            W10Column(
                id: "network", title: L.t("Mạng", "Network"),
                top: String(format: "%.0f%%", netPercent * 100),
                topHeat: netPercent,
                width: 88,
                heat: { W10.netHeat($0.netMbps) },
                text: { Fmt.netCell($0.netMbps) }
            )
        ]
    }

    private var sections: [W10Section<AppEntity>] {
        let key = ProcSortKey(rawValue: sortKey) ?? .memory
        let tree = presenter.tree
        return ProcessCategory.allCases.map { category in
            let source: [AppEntity]
            switch category {
            case .app:        source = tree.roots
            case .background: source = tree.background
            case .system:     source = tree.system
            }
            let rows = AppEntity.sorted(source, key: key, ascending: ascending)
            return W10Section(
                id: "\(category.rawValue)",
                title: "\(category.title) (\(rows.count))",
                rows: rows
            )
        }
    }

    // MARK: - Menu ngữ cảnh

    @ViewBuilder
    private func menu(for entity: AppEntity) -> some View {
        Button(L.t("Kết thúc tác vụ", "End task")) { presenter.forceQuit(entity) }
        Divider()
        Button(L.t("Chuyển tới chi tiết", "Go to details")) { onShowDetails(entity.id) }
        Button(L.t("Đưa ra trước", "Bring to front")) { presenter.activate(entity) }
            .disabled(!entity.isGUIApp)
        Button(L.t("Mở vị trí tệp", "Open file location")) { presenter.revealInFinder(entity) }
            .disabled(entity.path.isEmpty)
    }

    static func percent(_ value: Double) -> String {
        value < 0.05 ? "0%" : String(format: "%.1f%%", value)
    }
}

struct NameCell: View {
    let entity: AppEntity

    var body: some View {
        HStack(spacing: 5) {
            if let icon = entity.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(W10.textFaint)
                    .frame(width: 16, height: 16)
            }
            Text(entity.name)
                .font(W10.font())
                .foregroundColor(W10.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}

struct StatusCell: View {
    let entity: AppEntity

    var body: some View {
        HStack(spacing: 3) {
            if entity.isSuspended {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color(rgb: 0x3C9F40))
                Text(L.t("Tạm ngưng", "Suspended"))
                    .font(W10.font(10))
                    .foregroundColor(W10.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
