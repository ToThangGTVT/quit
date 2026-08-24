import SwiftUI

struct StartupTab: View {
    @Binding var selection: Set<String>
    @Binding var sortKey: String
    @Binding var ascending: Bool
    let items: [StartupItem]
    @State private var collapsed: Set<String> = []

    var body: some View {
        W10Grid(columns: columns,
                sections: [W10Section(id: "startup", title: nil, rows: rows)],
                selection: $selection,
                sortKey: $sortKey,
                ascending: $ascending,
                collapsed: $collapsed)
    }

    private var rows: [StartupItem] {
        let sorted: [StartupItem]
        switch sortKey {
        case "publisher": sorted = items.sorted { $0.publisher < $1.publisher }
        case "status":    sorted = items.sorted { ($0.enabled ? 0 : 1, $0.name) < ($1.enabled ? 0 : 1, $1.name) }
        case "scope":     sorted = items.sorted { ($0.scope, $0.name) < ($1.scope, $1.name) }
        default:          sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return ascending ? sorted : sorted.reversed()
    }

    private var columns: [W10Column<StartupItem>] {
        [
            W10Column(id: "name", title: L.t("Tên", "Name"), width: nil, minWidth: 240, trailing: false,
                      content: { item in
                          AnyView(HStack(spacing: 5) {
                              Image(systemName: "bolt.fill")
                                  .font(.system(size: 9))
                                  .foregroundColor(item.enabled ? Color(rgb: 0xD08A00) : W10.textFaint)
                                  .frame(width: 16)
                              Text(item.name).font(W10.font()).lineLimit(1).truncationMode(.middle)
                              Spacer(minLength: 0)
                          })
                      }),
            W10Column(id: "publisher", title: L.t("Nhà phát hành", "Publisher"), width: 150, trailing: false,
                      text: { $0.publisher }),
            W10Column(id: "scope", title: L.t("Phạm vi", "Scope"), width: 100, trailing: false, text: { $0.scope }),
            W10Column(id: "status", title: L.t("Trạng thái", "Status"), width: 90, trailing: false,
                      text: { $0.statusText }),
            W10Column(id: "impact", title: L.t("Tác động khi khởi động", "Startup impact"), width: 150, trailing: false,
                      sortable: false, text: { $0.impactText })
        ]
    }
}

struct ServicesTab: View {
    @Binding var selection: Set<String>
    @Binding var sortKey: String
    @Binding var ascending: Bool
    let items: [ServiceItem]
    @State private var collapsed: Set<String> = []

    var body: some View {
        W10Grid(columns: columns,
                sections: [W10Section(id: "services", title: nil, rows: rows)],
                selection: $selection,
                sortKey: $sortKey,
                ascending: $ascending,
                collapsed: $collapsed)
    }

    private var rows: [ServiceItem] {
        let sorted: [ServiceItem]
        switch sortKey {
        case "pid":    sorted = items.sorted { $0.pid < $1.pid }
        case "status": sorted = items.sorted { ($0.running ? 0 : 1, $0.id) < ($1.running ? 0 : 1, $1.id) }
        case "scope":  sorted = items.sorted { ($0.scope, $0.id) < ($1.scope, $1.id) }
        default:       sorted = items.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        }
        return ascending ? sorted : sorted.reversed()
    }

    private var columns: [W10Column<ServiceItem>] {
        [
            W10Column(id: "name", title: L.t("Tên", "Name"), width: nil, minWidth: 260, trailing: false,
                      content: { item in
                          AnyView(HStack(spacing: 5) {
                              Image(systemName: item.running ? "gearshape.fill" : "gearshape")
                                  .font(.system(size: 10))
                                  .foregroundColor(item.running ? W10.accent : W10.textFaint)
                                  .frame(width: 16)
                              Text(item.id).font(W10.font()).lineLimit(1).truncationMode(.middle)
                              Spacer(minLength: 0)
                          })
                      }),
            W10Column(id: "pid", title: "PID", width: 62, text: { $0.pidText }),
            W10Column(id: "description", title: L.t("Mô tả", "Description"), width: 190, trailing: false,
                      sortable: false, text: { $0.description }),
            W10Column(id: "status", title: L.t("Trạng thái", "Status"), width: 90, trailing: false,
                      text: { $0.statusText }),
            W10Column(id: "scope", title: L.t("Nhóm", "Group"), width: 100, trailing: false, text: { $0.scope })
        ]
    }
}
