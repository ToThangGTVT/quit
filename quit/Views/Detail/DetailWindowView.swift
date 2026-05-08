import SwiftUI

struct DetailWindowView: View {
    @Bindable var presenter: AppListPresenter
    @Bindable var router: AppRouter

    @State private var selection = Set<Int32>()

    private var appsRows: [AppEntity]       { presenter.appEntities.filter { $0.isRegular } }
    private var backgroundRows: [AppEntity] { presenter.appEntities.filter { !$0.isRegular } }

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
                            Color.clear.frame(width: 16, height: 16)
                        }
                        Text(entity.name).lineLimit(1)
                    }
                }
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
            } rows: {
                Section("Ứng dụng (\(appsRows.count))") {
                    ForEach(appsRows) { TableRow($0) }
                }
                Section("Nền (\(backgroundRows.count))") {
                    ForEach(backgroundRows) { TableRow($0) }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 440, minHeight: 480)
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
                Label(String(format: "CPU %.0f%%", min(totalCPU, 999)), systemImage: "cpu")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Label(String(format: "RAM %.0f MB", totalRAM), systemImage: "memorychip")
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
            let regular = presenter.appEntities.filter { $0.isRegular }.count
            let bg = presenter.appEntities.filter { !$0.isRegular }.count
            Text("\(regular) ứng dụng · \(bg) nền")
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
