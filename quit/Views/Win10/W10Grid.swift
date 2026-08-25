import SwiftUI

struct W10Column<Row: Identifiable> {
    var id: String
    var title: String
    var top: String? = nil          // dòng phần trăm phía trên tiêu đề
    var topHeat: Double = 0
    var width: CGFloat? = nil       // nil = cột giãn
    var minWidth: CGFloat = 150
    var trailing: Bool = true
    var sortable: Bool = true
    var heat: (Row) -> Double = { _ in 0 }
    var text: (Row) -> String = { _ in "" }
    var content: ((Row) -> AnyView)? = nil
}

struct W10Section<Row: Identifiable>: Identifiable {
    var id: String
    var title: String? = nil
    var rows: [Row]
    var summary: [String: String]? = nil
}

/// Bảng dữ liệu mô phỏng list-view của Task Manager: tiêu đề hai dòng có phần
/// trăm tổng, ô tô màu theo mức sử dụng, nhóm có thể thu gọn.
struct W10Grid<Row: Identifiable>: View where Row.ID: Hashable {
    var columns: [W10Column<Row>]
    var sections: [W10Section<Row>]
    @Binding var selection: Set<Row.ID>
    @Binding var sortKey: String
    @Binding var ascending: Bool
    @Binding var collapsed: Set<String>
    var rowHeight: CGFloat = 22
    var children: ((Row) -> [Row])? = nil
    var onDoubleClick: ((Row) -> Void)? = nil
    var menuBuilder: ((Row) -> AnyView)? = nil

    @State private var expanded: Set<Row.ID> = []

    var body: some View {
        // Tiêu đề nằm trong cùng ScrollView (pinned) để luôn khớp cột với thân bảng,
        // kể cả khi macOS chiếm chỗ cho thanh cuộn.
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(sections) { section in
                        if let title = section.title {
                            groupHeader(section, title: title)
                        }
                        if !collapsed.contains(section.id) {
                            ForEach(displayRows(section), id: \.id) { item in
                                rowView(item.row, depth: item.depth, expandable: item.expandable)
                            }
                        }
                    }
                } header: {
                    VStack(spacing: 0) {
                        header
                        Rectangle().fill(W10.border).frame(height: 1)
                    }
                    .background(W10.content)
                }
            }
        }
        .background(W10.content)
    }

    // MARK: - Tiêu đề

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.id) { column in
                headerCell(column)
            }
        }
        .frame(height: 44)
        .background(W10.content)
    }

    private func headerCell(_ column: W10Column<Row>) -> some View {
        let sorted = sortKey == column.id
        return ZStack(alignment: .leading) {
            if let tint = W10.heat(column.topHeat) {
                Rectangle().fill(tint)
            } else {
                Rectangle().fill(W10.content)
            }
            VStack(alignment: column.trailing ? .trailing : .leading, spacing: 0) {
                Spacer(minLength: 0)
                if let top = column.top {
                    Text(top)
                        .font(W10.font(11))
                        .foregroundColor(W10.heatText(column.topHeat))
                }
                Text(column.title)
                    .font(W10.font(12, sorted ? .semibold : .regular))
                    .foregroundColor(W10.heatText(column.topHeat))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: column.trailing ? .trailing : .leading)
            // Cột căn trái phải chừa chỗ cho mũi tên sắp xếp.
            .padding(.leading, sorted && !column.trailing ? 18 : 6)
            .padding(.trailing, 6)
            .padding(.bottom, 4)

            // Mũi tên sắp xếp: nằm sát trái, giữa theo chiều dọc.
            if sorted {
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(W10.heatText(column.topHeat).opacity(0.75))
                    .padding(.leading, 5)
            }
        }
        .frame(width: column.width, height: 44)
        .frame(minWidth: column.width == nil ? column.minWidth : nil,
               maxWidth: column.width == nil ? .infinity : nil)
        .contentShape(Rectangle())
        .onTapGesture {
            guard column.sortable else { return }
            if sortKey == column.id {
                ascending.toggle()
            } else {
                sortKey = column.id
                ascending = !column.trailing
            }
        }
    }

    // MARK: - Nhóm

    private func groupHeader(_ section: W10Section<Row>, title: String) -> some View {
        let isCollapsed = collapsed.contains(section.id)
        return HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                Group {
                    if index == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(W10.textDim)
                            Text(title)
                                .font(W10.font(12, .semibold))
                                .foregroundColor(Color(rgb: 0x2B2B2B))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    } else {
                        Text(section.summary?[column.id] ?? "")
                            .font(W10.font(11))
                            .foregroundColor(W10.textDim)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: column.trailing ? .trailing : .leading)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: column.width)
                .frame(minWidth: column.width == nil ? column.minWidth : nil,
                       maxWidth: column.width == nil ? .infinity : nil)
            }
        }
        .frame(height: 24)
        .background(W10.chromeAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(W10.gridLine).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
        }
    }

    // MARK: - Dòng

    private struct DisplayRow: Identifiable {
        let id: Row.ID
        let row: Row
        let depth: Int
        let expandable: Bool
    }

    private func displayRows(_ section: W10Section<Row>) -> [DisplayRow] {
        guard let children else {
            return section.rows.map { DisplayRow(id: $0.id, row: $0, depth: 0, expandable: false) }
        }
        var result: [DisplayRow] = []
        for row in section.rows {
            let kids = children(row)
            result.append(DisplayRow(id: row.id, row: row, depth: 0, expandable: !kids.isEmpty))
            if expanded.contains(row.id) {
                for kid in kids {
                    result.append(DisplayRow(id: kid.id, row: kid, depth: 1, expandable: false))
                }
            }
        }
        return result
    }

    @ViewBuilder
    private func rowView(_ row: Row, depth: Int, expandable: Bool) -> some View {
        W10Row(columns: columns,
               row: row,
               depth: depth,
               expandable: expandable,
               isExpanded: expanded.contains(row.id),
               isSelected: selection.contains(row.id),
               rowHeight: rowHeight,
               showsTree: children != nil,
               menuBuilder: menuBuilder,
               onToggleExpand: {
                   if expanded.contains(row.id) { expanded.remove(row.id) }
                   else { expanded.insert(row.id) }
               },
               onClick: { clickCount, commandKey in
                   if clickCount >= 2 {
                       onDoubleClick?(row)
                   } else if commandKey {
                       if selection.contains(row.id) { selection.remove(row.id) }
                       else { selection.insert(row.id) }
                   } else {
                       selection = [row.id]
                   }
               })
    }
}

/// Một dòng của bảng. Tách thành view riêng để trạng thái hover chỉ vẽ lại
/// đúng dòng đó thay vì toàn bộ bảng.
private struct W10Row<Row: Identifiable>: View where Row.ID: Hashable {
    let columns: [W10Column<Row>]
    let row: Row
    let depth: Int
    let expandable: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let rowHeight: CGFloat
    let showsTree: Bool
    let menuBuilder: ((Row) -> AnyView)?
    let onToggleExpand: () -> Void
    /// (số lần bấm, có giữ ⌘ hay không)
    let onClick: (Int, Bool) -> Void

    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                cell(column, isFirst: index == 0)
            }
        }
        .frame(height: rowHeight)
        .overlay {
            if isSelected { Rectangle().strokeBorder(W10.selectionEdge, lineWidth: 1) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Chỉ một tap gesture: gắn thêm gesture 2-lần-bấm sẽ khiến SwiftUI đợi hết
        // ngưỡng double-click rồi mới chọn dòng, cảm giác rất trễ.
        .onTapGesture {
            onClick(NSApp.currentEvent?.clickCount ?? 1,
                    NSEvent.modifierFlags.contains(.command))
        }

        if let menuBuilder {
            content.contextMenu { menuBuilder(row) }
        } else {
            content
        }
    }

    private func cell(_ column: W10Column<Row>, isFirst: Bool) -> some View {
        let heatValue = column.heat(row)
        return ZStack {
            // Nền chọn / hover thay hẳn màu nhiệt, không chồng lên (chồng thì ra
            // màu vàng-xanh lem nhem như bản trước).
            if isSelected {
                Rectangle().fill(W10.selection)
            } else if hovering {
                Rectangle().fill(W10.hover)
            } else if let tint = W10.heat(heatValue) {
                Rectangle().fill(tint)
            }
            HStack(spacing: 2) {
                if showsTree, isFirst {
                    if depth > 0 { Spacer().frame(width: 15) }
                    if expandable {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(W10.textDim)
                            .frame(width: 12)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onToggleExpand)
                    } else {
                        Spacer().frame(width: 12)
                    }
                }
                if let custom = column.content {
                    custom(row)
                } else {
                    Text(column.text(row))
                        .font(W10.font())
                        .monospacedDigit()
                        .foregroundColor(isSelected || hovering ? W10.text : W10.heatText(heatValue))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: column.trailing ? .trailing : .leading)
            .padding(.horizontal, 6)
        }
        .frame(width: column.width)
        .frame(minWidth: column.width == nil ? column.minWidth : nil,
               maxWidth: column.width == nil ? .infinity : nil)
    }
}
