import SwiftUI

struct DetailWindowView: View {
    @Bindable var presenter: AppListPresenter
    @Bindable var router: AppRouter

    @State private var selection = Set<Int32>()

    private var appsRows: [AppEntity]       { presenter.appEntities.filter { $0.isRegular } }
    private var backgroundRows: [AppEntity] { presenter.appEntities.filter { $0.isGUIApp && !$0.isRegular } }
    private var processRows: [AppEntity]    { presenter.appEntities.filter { !$0.isGUIApp } }

    private static func formatNet(_ kbs: Double) -> String {
        kbs >= 1024
            ? String(format: "%.1f MB/s", kbs / 1024)
            : String(format: "%.0f KB/s", kbs)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Table(selection: $selection, sortOrder: $presenter.sortOrder) {
                TableColumn("Tên", value: \AppEntity.name) { entity in
                    HStack(spacing: 6) {
                        if let icon = entity.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "gearshape.fill")
                                .frame(width: 16, height: 16)
                                .foregroundColor(.secondary)
                        }
                        Text(entity.name).lineLimit(1)
                    }
                }
                TableColumn("PID") { entity in
                    Text("\(entity.id)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
                .width(50)
                TableColumn("CPU", value: \AppEntity.cpu) { entity in
                    Text(String(format: "%.1f%%", entity.cpu))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(entity.cpu > 50 ? .red : entity.cpu > 15 ? .orange : .primary)
                }
                .width(65)
                TableColumn("RAM", value: \AppEntity.memory) { entity in
                    Text(entity.memory >= 1024
                         ? String(format: "%.1f GB", entity.memory / 1024)
                         : String(format: "%.0f MB", entity.memory))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(80)
                TableColumn("↓ Mạng", value: \AppEntity.netRxKBs) { entity in
                    Text(entity.netRxKBs > 0
                         ? Self.formatNet(entity.netRxKBs)
                         : "-")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(entity.netRxKBs > 100 ? .blue : .primary)
                }
                .width(75)
                TableColumn("↑ Mạng", value: \AppEntity.netTxKBs) { entity in
                    Text(entity.netTxKBs > 0
                         ? Self.formatNet(entity.netTxKBs)
                         : "-")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(entity.netTxKBs > 100 ? .orange : .primary)
                }
                .width(75)
            } rows: {
                Section("Ứng dụng (\(appsRows.count))") {
                    ForEach(appsRows) { TableRow($0) }
                }
                Section("Nền (\(backgroundRows.count))") {
                    ForEach(backgroundRows) { TableRow($0) }
                }
                Section("Tiến trình (\(processRows.count))") {
                    ForEach(processRows) { TableRow($0) }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Toggle("Luôn trên đầu", isOn: $router.isAlwaysOnTop)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Spacer()
            let totalRAM = presenter.appEntities.reduce(0) { $0 + $1.memory }
            let totalCPU = presenter.appEntities.reduce(0) { $0 + $1.cpu }
            HStack(spacing: 16) {
                Label(String(format: "CPU %.0f%%", min(totalCPU, 100)), systemImage: "cpu")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Label(String(format: "RAM %.0f MB", totalRAM), systemImage: "memorychip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Label("↓ \(Self.formatNet(presenter.systemStats.netRxKBs))  ↑ \(Self.formatNet(presenter.systemStats.netTxKBs))", systemImage: "network")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Button(action: { presenter.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footer: some View {
        HStack {
            let regular = appsRows.count
            let bg = backgroundRows.count
            let procs = processRows.count
            Text("\(regular) ứng dụng · \(bg) nền · \(procs) tiến trình")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Buộc thoát") { forceQuitSelected() }
                .disabled(selection.isEmpty)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func forceQuitSelected() {
        for pid in selection {
            if let entity = presenter.appEntities.first(where: { $0.id == pid }) {
                presenter.forceQuit(entity)
            }
        }
        selection.removeAll()
    }
}
