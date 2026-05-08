import SwiftUI

struct MenuBarView: View {
    var presenter: AppListPresenter
    var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuBarHeaderView(presenter: presenter)
            appList
            HStack {
                Button("Mở cửa sổ") { router.openDetailWindow(presenter: presenter) }
                    .controlSize(.small)
                Spacer()
                Button("Thoát") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var appList: some View {
        Group {
            if presenter.appEntities.isEmpty {
                Text("Đang quét ứng dụng...").foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(presenter.appEntities) { entity in
                    HStack {
                        Button(action: { entity.runningApp.activate(options: .activateAllWindows) }) {
                            HStack {
                                if let icon = entity.icon {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                }
                                VStack(alignment: .leading) {
                                    Text(entity.name).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(String(format: "%.0f", entity.memory)) MB")
                                        Text("·").foregroundColor(.gray.opacity(0.5))
                                        Text("CPU \(String(format: "%.1f", entity.cpu))%")
                                    }
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: { presenter.forceQuit(entity) }) {
                            Image(systemName: "xmark.circle.fill").resizable().frame(width: 16, height: 16)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .frame(height: 350)
            }
        }
    }
}

struct MenuBarHeaderView: View {
    var presenter: AppListPresenter

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Ứng dụng đang mở (\(presenter.appEntities.count))")
                    .font(.headline)
                HStack(spacing: 4) {
                    let totalRAM = presenter.appEntities.reduce(0) { $0 + $1.memory }
                    Text("RAM: \(String(format: "%.1f", totalRAM)) MB")
                        .foregroundColor(.blue)
                    Text("|").foregroundColor(.gray.opacity(0.5))
                    Text("Áp lực: \(presenter.systemStats.pressureText) (\(presenter.systemStats.memoryPressure))")
                        .foregroundColor(presenter.systemStats.pressureColor)
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
            }
            Spacer()
            Button(action: { presenter.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }
}

struct MenuBarLabel: View {
    var presenter: AppListPresenter

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "memorychip")
            Text("\(Int(presenter.systemStats.memoryUsagePercentage))%")
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }
}
