import SwiftUI

struct W10Series {
    var samples: [Double]      // đã chuẩn hoá 0...1
    var line: Color
    var fill: Color? = nil
    var dashed: Bool = false
}

/// Đồ thị 60 giây kiểu Task Manager: lưới mờ, vùng tô nhạt, đường viền màu.
struct W10Graph: View {
    var series: [W10Series]
    var capacity: Int = AppListPresenter.historyCapacity
    var showGrid: Bool = true
    var gridColor: Color = W10.gridLine
    var borderColor: Color? = nil
    var gridColumns: Int = 10
    var gridRows: Int = 5

    @Environment(\.displayScale) private var displayScale

    /// Đường đồ thị là nét xiên nên không căn được vào lưới điểm ảnh; ở màn 1x
    /// nét 1.2pt trải sang hai cột pixel thành vệt mờ, nên hạ về đúng 1 điểm ảnh.
    private var curveWidth: CGFloat { displayScale >= 2 ? 1.2 : 1 }

    var body: some View {
        Canvas { context, size in
            if showGrid {
                var grid = Path()
                // Toạ độ chia đều hầu như luôn ra số lẻ; nếu vẽ thẳng thì mỗi đường
                // kẻ bị khử răng cưa thành hai hàng pixel nhạt (rõ nhất ở màn 1x).
                for column in 1..<gridColumns {
                    let raw = size.width * CGFloat(column) / CGFloat(gridColumns)
                    let x = W10.snap(raw, width: 1, scale: displayScale)
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for row in 1..<gridRows {
                    let raw = size.height * CGFloat(row) / CGFloat(gridRows)
                    let y = W10.snap(raw, width: 1, scale: displayScale)
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(gridColor), lineWidth: 1)
            }

            for item in series {
                let samples = item.samples
                guard samples.count >= 2, capacity > 1 else { continue }
                let offset = max(capacity - samples.count, 0)
                func point(_ index: Int) -> CGPoint {
                    let x = size.width * CGFloat(offset + index) / CGFloat(capacity - 1)
                    let value = min(max(samples[index], 0), 1)
                    return CGPoint(x: x, y: size.height - size.height * CGFloat(value))
                }

                var line = Path()
                line.move(to: point(0))
                for index in 1..<samples.count { line.addLine(to: point(index)) }

                if let fill = item.fill {
                    var area = line
                    area.addLine(to: CGPoint(x: point(samples.count - 1).x, y: size.height))
                    area.addLine(to: CGPoint(x: point(0).x, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .color(fill))
                }

                let style = StrokeStyle(lineWidth: curveWidth,
                                        dash: item.dashed ? [3, 2] : [])
                context.stroke(line, with: .color(item.line), style: style)
            }
        }
        .overlay {
            if let borderColor {
                Rectangle().strokeBorder(borderColor, lineWidth: 1)
            }
        }
    }
}

/// Khung đồ thị lớn kèm 4 nhãn góc như tab Hiệu suất của Task Manager.
/// Nội dung có thể là một đồ thị hoặc lưới đồ thị từng lõi.
struct W10GraphPanel<Content: View>: View {
    let title: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(W10.font(12)).foregroundColor(W10.textDim)
                Spacer()
                Text(topRight).font(W10.font(12)).foregroundColor(W10.textDim)
            }
            content()
            HStack {
                Text(bottomLeft).font(W10.font(12)).foregroundColor(W10.textDim)
                Spacer()
                Text(bottomRight).font(W10.font(12)).foregroundColor(W10.textDim)
            }
        }
    }
}

/// Thanh "Thành phần bộ nhớ" của Task Manager.
struct W10CompositionBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let borderColor: Color

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let widths = snappedWidths(across: geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: widths[index])
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(borderColor.opacity(0.6)).frame(width: 1)
                        }
                }
            }
        }
        .overlay(Rectangle().strokeBorder(borderColor, lineWidth: 1))
    }

    /// Bề rộng từng phần, làm tròn ranh giới về số nguyên điểm ảnh (phần dư dồn
    /// sang phần kế tiếp) để vạch ngăn không rơi vào giữa hai điểm ảnh.
    private func snappedWidths(across width: CGFloat) -> [CGFloat] {
        let scale = max(displayScale, 1)
        let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
        var edge: CGFloat = 0
        var previousEdge: CGFloat = 0
        return segments.map { segment in
            edge += width * CGFloat(segment.value / total)
            let snapped = min((edge * scale).rounded() / scale, width)
            defer { previousEdge = snapped }
            return max(snapped - previousEdge, 0)
        }
    }
}
