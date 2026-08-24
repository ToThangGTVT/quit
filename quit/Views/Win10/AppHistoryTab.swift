import SwiftUI

struct AppHistoryTab: View {
    var presenter: AppListPresenter
    @Binding var sortKey: String
    @Binding var ascending: Bool
    @State private var selection = Set<String>()
    @State private var collapsed: Set<String> = []

    var body: some View {
        W10Grid(columns: columns,
                sections: [W10Section(id: "apps", title: nil, rows: rows)],
                selection: $selection,
                sortKey: $sortKey,
                ascending: $ascending,
                collapsed: $collapsed)
    }

    private var rows: [AppListPresenter.AppUsage] {
        let list = presenter.appUsage
        let sorted: [AppListPresenter.AppUsage]
        switch sortKey {
        case "name":    sorted = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "network": sorted = list.sorted { $0.network < $1.network }
        default:        sorted = list.sorted { $0.cpuTime < $1.cpuTime }
        }
        return ascending ? sorted : sorted.reversed()
    }

    private var columns: [W10Column<AppListPresenter.AppUsage>] {
        [
            W10Column(id: "name", title: L.t("Tên", "Name"), width: nil, minWidth: 240, trailing: false,
                      content: { usage in
                          AnyView(HStack(spacing: 5) {
                              if let icon = usage.icon {
                                  Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                              } else {
                                  Image(systemName: "app.dashed")
                                      .font(.system(size: 10))
                                      .foregroundColor(W10.textFaint)
                                      .frame(width: 16, height: 16)
                              }
                              Text(usage.name).font(W10.font()).lineLimit(1)
                              Spacer(minLength: 0)
                          })
                      }),
            W10Column(id: "cpuTime", title: L.t("Thời gian CPU", "CPU time"), width: 120,
                      text: { Fmt.cpuTime($0.cpuTime) }),
            W10Column(id: "network", title: L.t("Mạng", "Network"), width: 110,
                      text: { Fmt.bytesAuto($0.network) })
        ]
    }

}
