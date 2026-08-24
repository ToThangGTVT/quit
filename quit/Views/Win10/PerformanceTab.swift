import SwiftUI
import AppKit

enum PerfResource: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network, gpu, bluetooth, sensors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu:       return "CPU"
        case .memory:    return L.t("Bộ nhớ", "Memory")
        case .disk:      return L.t("Đĩa", "Disk")
        case .network:   return L.t("Mạng", "Network")
        case .gpu:       return "GPU"
        case .bluetooth: return "Bluetooth"
        case .sensors:   return L.t("Cảm biến", "Sensors")
        }
    }
}

struct PerformanceTab: View {
    var presenter: AppListPresenter
    @Bindable var state: TaskManagerState
    @State private var adapter = NetworkAdapterInfo.current()

    private let hw = HardwareInfo.current

    /// Dưới ngưỡng này thì ẩn cột thông tin phần cứng bên phải và để khối số liệu xuống dòng.
    private static let infoColumnThreshold: CGFloat = 650
    private static let sidebarWidth: CGFloat = 196
    private static let narrowSidebarWidth: CGFloat = 150

    private var selected: PerfResource { state.perfResource }
    private var stats: SystemStats { presenter.systemStats }
    private var summary: Bool { state.perfSummaryView }

    var body: some View {
        GeometryReader { outer in
            let narrow = outer.size.width < 760
            HStack(spacing: 0) {
                if !summary {
                    sidebar(width: narrow ? Self.narrowSidebarWidth : Self.sidebarWidth)
                    Rectangle().fill(W10.border).frame(width: 1)
                }
                GeometryReader { inner in
                    detail(compact: inner.size.width < Self.infoColumnThreshold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(summary ? 8 : 14)
                .background(W10.content)
            }
        }
        .background(W10.content)
        .contextMenu { contextMenuItems }
        .onAppear {
            adapter = NetworkAdapterInfo.current()
            if selected == .bluetooth { presenter.refreshBluetooth() }
        }
    }

    // MARK: - Menu chuột phải (giống Task Manager)

    @ViewBuilder
    private var contextMenuItems: some View {
        if selected == .cpu {
            Menu(L.t("Đổi đồ thị thành", "Change graph to")) {
                Picker("", selection: $state.perfGraphMode) {
                    Text(L.t("Mức sử dụng tổng thể", "Overall utilization")).tag(PerfGraphMode.overall)
                    Text(L.t("Bộ xử lý logic", "Logical processors")).tag(PerfGraphMode.logicalProcessors)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Toggle(L.t("Hiện thời gian nhân", "Show kernel times"), isOn: $state.showKernelTimes)
            Divider()
        }
        Toggle(L.t("Chế độ đồ thị tóm tắt", "Graph summary view"), isOn: $state.perfSummaryView)
        Menu("Xem") {
            Picker("", selection: $state.perfResource) {
                ForEach(PerfResource.allCases) { resource in
                    Text(resource.title).tag(resource)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Divider()
        Button(L.t("Sao chép", "Copy")) { copySummary() }
            .keyboardShortcut("c")
    }

    private func copySummary() {
        let pane = paneData()
        var lines = [pane.title, pane.subtitle, ""]
        lines += pane.values.map { "\($0.0): \($0.1)" }
        if !pane.info.isEmpty {
            lines.append("")
            lines += pane.info.map { "\($0.0.replacingOccurrences(of: ":", with: "")): \($0.1)" }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: - Cột trái

    private func sidebar(width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(PerfResource.allCases) { resource in
                    sidebarItem(resource, width: width)
                }
            }
        }
        .frame(width: width)
        .background(W10.content)
    }

    private func sidebarItem(_ resource: PerfResource, width: CGFloat) -> some View {
        let isSelected = selected == resource
        return HStack(spacing: 7) {
            Rectangle()
                .fill(isSelected ? W10.accent : Color.clear)
                .frame(width: 3)
            Group {
                if resource == .sensors {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 15))
                        .foregroundColor(Color(rgb: 0xC0392B))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(Rectangle().stroke(Color(rgb: 0xC0392B), lineWidth: 1))
                } else if resource == .bluetooth {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 15))
                        .foregroundColor(W10.btLine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(Rectangle().stroke(W10.btLine, lineWidth: 1))
                } else {
                    W10Graph(series: [series(for: resource, fillOnly: true)],
                             showGrid: false,
                             borderColor: lineColor(resource))
                }
            }
            .frame(width: width < 170 ? 44 : 64, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(resource))
                    .font(W10.font(12))
                    .foregroundColor(W10.text)
                    .lineLimit(1)
                Text(sidebarSubtitle(resource))
                    .font(W10.font(11))
                    .foregroundColor(W10.textDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(isSelected ? Color(rgb: 0xE9F3FB) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            state.perfResource = resource
            if resource == .bluetooth { presenter.refreshBluetooth() }
        }
    }

    // MARK: - Ngăn phải

    private func detail(compact: Bool) -> some View {
        let pane = paneData()
        return VStack(alignment: .leading, spacing: 10) {
            if !summary {
                header(pane.title, pane.subtitle)
            }
            graphs
            if !summary {
                bottom(compact: compact, values: pane.values, info: pane.info)
            }
        }
    }

    @ViewBuilder
    private var graphs: some View {
        switch selected {
        case .cpu:       cpuGraphs
        case .memory:    memoryGraphs
        case .disk:      diskGraphs
        case .network:   networkGraphs
        case .gpu:       gpuGraphs
        case .bluetooth: bluetoothList
        case .sensors:   sensorsList
        }
    }

    @ViewBuilder
    private var cpuGraphs: some View {
        W10GraphPanel(title: state.perfGraphMode == .overall
                        ? L.t("% Sử dụng", "% Utilization")
                        : L.t("% Sử dụng — \(hw.performanceCores) nhân P (hiệu năng), \(hw.efficiencyCores) nhân E (tiết kiệm điện)",
                              "% Utilization — \(hw.performanceCores) P cores (performance), \(hw.efficiencyCores) E cores (efficiency)"),
                      topRight: "100%", bottomLeft: L.t("60 giây", "60 seconds"), bottomRight: "0") {
            if state.perfGraphMode == .logicalProcessors, !presenter.perCoreHistory.isEmpty {
                coreGrid
            } else {
                W10Graph(series: cpuSeries,
                         gridColor: W10.cpuFill.opacity(0.8),
                         borderColor: W10.cpuLine)
            }
        }
    }

    private var cpuSeries: [W10Series] {
        var result = [series(for: .cpu)]
        if state.showKernelTimes {
            result.append(W10Series(samples: presenter.cpuKernelHistory,
                                    line: Color(rgb: 0x0A3D66),
                                    fill: Color(rgb: 0x2C6FA8).opacity(0.55)))
        }
        return result
    }

    private var coreGrid: some View {
        let cores = presenter.perCoreHistory
        let columns = min(4, max(1, cores.count))
        let rows = Int(ceil(Double(cores.count) / Double(columns)))
        return VStack(spacing: 3) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < cores.count {
                            coreCell(index, samples: cores[index])
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    /// Một ô lõi: tên lõi + nhãn cụm (P = hiệu năng, E = tiết kiệm điện) + % hiện tại.
    private func coreCell(_ index: Int, samples: [Double]) -> some View {
        let clusters = hw.coreClusters
        let cluster = index < clusters.count ? clusters[index] : ""
        let usage = index < stats.perCore.count ? stats.perCore[index] : 0
        return W10Graph(series: [W10Series(samples: samples,
                                           line: W10.cpuLine,
                                           fill: W10.cpuFill)],
                        gridColor: W10.cpuFill.opacity(0.8),
                        borderColor: W10.cpuLine,
                        gridColumns: 4, gridRows: 2)
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 3) {
                    Text("CPU \(index)")
                        .font(W10.font(10))
                        .foregroundColor(W10.textDim)
                    if !cluster.isEmpty {
                        Text(cluster)
                            .font(W10.font(9, .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(cluster == "P" ? W10.cpuLine : Color(rgb: 0x5B7C99))
                    }
                }
                .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(String(format: "%.0f%%", usage))
                    .font(W10.font(10))
                    .foregroundColor(W10.textDim)
                    .padding(4)
            }
    }

    @ViewBuilder
    private var memoryGraphs: some View {
        W10GraphPanel(title: L.t("Sử dụng bộ nhớ", "Memory usage"), topRight: Fmt.gb(stats.memTotal),
                      bottomLeft: L.t("60 giây", "60 seconds"), bottomRight: "0") {
            W10Graph(series: [series(for: .memory)],
                     gridColor: W10.memFill.opacity(0.8),
                     borderColor: W10.memLine)
        }
        if !summary {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("Thành phần bộ nhớ", "Memory composition")).font(W10.font(11)).foregroundColor(W10.textDim)
                W10CompositionBar(segments: [
                    .init(id: "app", value: Double(stats.memApp), color: W10.memFill),
                    .init(id: "wired", value: Double(stats.memWired), color: W10.memLine.opacity(0.55)),
                    .init(id: "compressed", value: Double(stats.memCompressed), color: W10.memLine.opacity(0.35)),
                    .init(id: "free", value: Double(stats.memAvailable), color: Color(rgb: 0xF3ECF7))
                ], borderColor: W10.memLine)
                .frame(height: 30)
                FlowLayout(spacing: 12, lineSpacing: 4) {
                    legend(L.t("Ứng dụng", "Apps"), W10.memFill)
                    legend("Wired", W10.memLine.opacity(0.55))
                    legend(L.t("Đã nén", "Compressed"), W10.memLine.opacity(0.35))
                    legend(L.t("Khả dụng", "Available"), Color(rgb: 0xF3ECF7))
                }
            }
        }
    }

    @ViewBuilder
    private var diskGraphs: some View {
        W10GraphPanel(title: L.t("% Thời gian hoạt động", "% Active time"), topRight: "100%",
                      bottomLeft: L.t("60 giây", "60 seconds"), bottomRight: "0") {
            W10Graph(series: [series(for: .disk)],
                     gridColor: W10.diskFill.opacity(0.9),
                     borderColor: W10.diskLine)
        }
        W10GraphPanel(title: L.t("Tốc độ truyền đĩa", "Disk transfer rate"), topRight: Fmt.rate(presenter.diskScaleKBs),
                      bottomLeft: L.t("60 giây", "60 seconds"), bottomRight: "0") {
            W10Graph(series: [
                W10Series(samples: presenter.diskReadHistory.map { $0 / presenter.diskScaleKBs },
                          line: W10.diskLine, fill: W10.diskFill.opacity(0.6)),
                W10Series(samples: presenter.diskWriteHistory.map { $0 / presenter.diskScaleKBs },
                          line: W10.diskLine.opacity(0.7), dashed: true)
            ],
            gridColor: W10.diskFill.opacity(0.9),
            borderColor: W10.diskLine)
        }
    }

    private var networkGraphs: some View {
        W10GraphPanel(title: L.t("Thông lượng", "Throughput"),
                      topRight: presenter.netScaleMbps < 1
                        ? String(format: "%.0f Kbps", presenter.netScaleMbps * 1000)
                        : String(format: "%.0f Mbps", presenter.netScaleMbps),
                      bottomLeft: L.t("60 giây", "60 seconds"), bottomRight: "0") {
            W10Graph(series: [
                W10Series(samples: presenter.netRxHistory.map { $0 / presenter.netScaleMbps },
                          line: W10.netLine, fill: W10.netFill.opacity(0.7)),
                W10Series(samples: presenter.netTxHistory.map { $0 / presenter.netScaleMbps },
                          line: W10.netLine.opacity(0.8), dashed: true)
            ],
            gridColor: W10.netFill.opacity(0.9),
            borderColor: W10.netLine)
        }
    }

    private var gpuGraphs: some View {
        W10GraphPanel(title: L.t("% Sử dụng GPU", "% GPU utilization"), topRight: "100%",
                      bottomLeft: L.t("60 giây", "60 seconds"), bottomRight: "0") {
            W10Graph(series: [series(for: .gpu)],
                     gridColor: W10.gpuFill.opacity(0.9),
                     borderColor: W10.gpuLine)
        }
    }

    private var bluetoothList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(L.t("Thiết bị", "Device")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L.t("Loại", "Type")).frame(width: 120, alignment: .leading)
                Text("Pin").frame(width: 130, alignment: .leading)
                Text("RSSI").frame(width: 60, alignment: .trailing)
                Text(L.t("Trạng thái", "Status")).frame(width: 90, alignment: .trailing)
            }
            .font(W10.font(11))
            .foregroundColor(W10.textDim)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .overlay(alignment: .bottom) { Rectangle().fill(W10.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(presenter.bluetoothDevices) { device in
                        HStack(spacing: 0) {
                            HStack(spacing: 5) {
                                Image(systemName: device.connected ? "dot.radiowaves.right" : "circle.dotted")
                                    .font(.system(size: 10))
                                    .foregroundColor(device.connected ? W10.btLine : W10.textFaint)
                                Text(device.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(device.kind).frame(width: 120, alignment: .leading).lineLimit(1)
                            Text(device.batteryText).frame(width: 130, alignment: .leading).lineLimit(1)
                            Text(device.rssi.map { "\($0) dBm" } ?? "—")
                                .frame(width: 60, alignment: .trailing)
                            Text(device.connected ? L.t("Đã kết nối", "Connected") : L.t("Đã ghép nối", "Paired"))
                                .frame(width: 90, alignment: .trailing)
                                .foregroundColor(device.connected ? W10.btLine : W10.textDim)
                        }
                        .font(W10.font())
                        .foregroundColor(W10.text)
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                    }
                    if presenter.bluetoothDevices.isEmpty {
                        Text(L.t("Không có thiết bị nào được ghép nối", "No paired devices"))
                            .font(W10.font())
                            .foregroundColor(W10.textDim)
                            .padding(.top, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(Rectangle().stroke(W10.border, lineWidth: 1))
    }

    private var sensorsList: some View {
        let sensors = stats.sensors
        return VStack(alignment: .leading, spacing: 10) {
            W10GraphPanel(title: L.t("Nhiệt độ CPU", "CPU temperature"), topRight: "110°C",
                          bottomLeft: L.t("60 giây", "60 seconds"), bottomRight: "0") {
                W10Graph(series: [series(for: .sensors)],
                         gridColor: Color(rgb: 0xF5D0CC),
                         borderColor: Color(rgb: 0xC0392B))
            }

            if !sensors.fans.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.t("Quạt", "Fans")).font(W10.font(12)).foregroundColor(W10.textDim)
                    ForEach(sensors.fans) { fan in
                        HStack(spacing: 8) {
                            Text(fan.name).font(W10.font()).frame(width: 70, alignment: .leading)
                            Text(fan.rpmText).font(W10.font()).monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color(rgb: 0xF3F3F3))
                                    Rectangle().fill(Color(rgb: 0xC0392B).opacity(0.75))
                                        .frame(width: geo.size.width * fan.percent)
                                }
                                .overlay(Rectangle().stroke(W10.border, lineWidth: 1))
                            }
                            .frame(height: 14)
                            Text(String(format: "%.0f – %.0f", fan.minRPM, fan.maxRPM))
                                .font(W10.font(11)).foregroundColor(W10.textDim)
                                .frame(width: 110, alignment: .trailing)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(L.t("Nhóm cảm biến", "Sensor group")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L.t("Trung bình", "Average")).frame(width: 110, alignment: .trailing)
                    Text(L.t("Cao nhất", "Maximum")).frame(width: 110, alignment: .trailing)
                    Text(L.t("Số cảm biến", "Sensors")).frame(width: 110, alignment: .trailing)
                }
                .font(W10.font(12))
                .foregroundColor(W10.textDim)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .overlay(alignment: .bottom) { Rectangle().fill(W10.border).frame(height: 1) }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(SensorGroup.allCases, id: \.rawValue) { group in
                            let list = sensors.values(in: group)
                            if !list.isEmpty {
                                HStack(spacing: 0) {
                                    Text(group.title).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(SensorsInfo.text(sensors.average(group)))
                                        .frame(width: 110, alignment: .trailing)
                                    Text(SensorsInfo.text(sensors.maximum(group)))
                                        .frame(width: 110, alignment: .trailing)
                                    Text("\(list.count)").frame(width: 110, alignment: .trailing)
                                }
                                .font(W10.font())
                                .monospacedDigit()
                                .foregroundColor(W10.text)
                                .padding(.horizontal, 6)
                                .frame(height: 24)
                            }
                        }
                        if !sensors.available {
                            Text(L.t("Không đọc được cảm biến", "No sensors available"))
                                .font(W10.font())
                                .foregroundColor(W10.textDim)
                                .padding(.top, 12)
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(W10.border, lineWidth: 1))
        }
    }

    // MARK: - Dữ liệu từng ngăn (dùng chung cho hiển thị và lệnh Sao chép)

    private func paneData() -> (title: String, subtitle: String,
                                values: [(String, String)], info: [(String, String)]) {
        switch selected {
        case .cpu:
            return ("CPU", hw.cpuName,
                    [(L.t("Mức sử dụng", "Utilization"), String(format: "%.0f%%", stats.cpuUsage)),
                     (L.t("Nhân hiệu năng", "Performance cores"), String(format: "%.0f%%", stats.performanceUsage)),
                     (L.t("Nhân tiết kiệm", "Efficiency cores"), String(format: "%.0f%%", stats.efficiencyUsage)),
                     (L.t("Tiến trình", "Processes"), "\(stats.processCount)"),
                     (L.t("Luồng", "Threads"), "\(stats.threadCount)"),
                     (L.t("Bộ mô tả", "Handles"), "\(stats.handleCount)"),
                     (L.t("Thời gian hoạt động", "Up time"), stats.uptimeText),
                     (L.t("Nhiệt độ", "Temperature"), SensorsInfo.text(stats.sensors.cpuTemperature)),
                     (L.t("Quạt", "Fan"), stats.sensors.fans.first?.rpmText ?? "—")],
                    [(L.t("Tốc độ tối đa (P):", "Max speed (P):"), hw.baseSpeedText),
                     (L.t("Tốc độ tối đa (E):", "Max speed (E):"), hw.efficiencySpeedText),
                     (L.t("Số lõi:", "Cores:"), "\(hw.physicalCores)"),
                     (L.t("Lõi P / E:", "P / E cores:"), "\(hw.performanceCores) / \(hw.efficiencyCores)"),
                     (L.t("Bộ xử lý logic:", "Logical processors:"), "\(hw.logicalCores)"),
                     (L.t("Kiến trúc:", "Architecture:"), hw.isAppleSilicon ? "arm64" : "x86_64"),
                     (L.t("Bộ đệm L1:", "L1 cache:"), Fmt.bytesAuto(hw.l1)),
                     (L.t("Bộ đệm L2 (P/E):", "L2 cache (P/E):"),
                      "\(Fmt.bytesAuto(hw.l2Performance)) / \(Fmt.bytesAuto(hw.l2Efficiency))"),
                     (L.t("Bộ đệm L3:", "L3 cache:"), hw.l3 > 0 ? Fmt.bytesAuto(hw.l3) : "—"),
                     (L.t("Dòng đệm:", "Cache line:"), "\(hw.cacheLineSize) B"),
                     (L.t("Kiểu máy:", "Model:"), hw.machineModel),
                     (L.t("Bảng mạch:", "Board:"), hw.targetType),
                     (L.t("Hệ điều hành:", "OS:"), hw.osVersion)])
        case .memory:
            return (L.t("Bộ nhớ", "Memory"), Fmt.gb(stats.memTotal),
                    [(L.t("Đang dùng (đã nén)", "In use (compressed)"), "\(Fmt.gb(stats.memUsed)) (\(Fmt.mb(stats.memCompressed)))"),
                     (L.t("Khả dụng", "Available"), Fmt.gb(stats.memAvailable)),
                     (L.t("Đã lưu đệm", "Cached"), Fmt.gb(stats.memCached)),
                     ("Wired", Fmt.gb(stats.memWired)),
                     ("Swap", "\(Fmt.mb(stats.swapUsed)) / \(Fmt.gb(stats.swapTotal))")],
                    [(L.t("Tổng dung lượng:", "Total capacity:"), Fmt.gb(hw.memTotal)),
                     (L.t("Áp lực bộ nhớ:", "Memory pressure:"), stats.pressureText),
                     (L.t("Đã dùng:", "Used:"), String(format: "%.0f%%", stats.memoryUsagePercentage)),
                     (L.t("Kích thước trang:", "Page size:"), "\(hw.pageSize / 1024) KB"),
                     (L.t("Swap tổng:", "Swap total:"), Fmt.gb(stats.swapTotal)),
                     (L.t("Kiểu máy:", "Model:"), hw.machineModel),
                     (L.t("Hệ điều hành:", "OS:"), hw.osVersion)])
        case .disk:
            return (L.t("Đĩa 0 (\(hw.diskName))", "Disk 0 (\(hw.diskName))"), hw.isAppleSilicon ? "SSD" : L.t("Ổ cứng", "Hard drive"),
                    [(L.t("Thời gian hoạt động", "Active time"), String(format: "%.0f%%", stats.diskActive)),
                     (L.t("Tốc độ đọc", "Read speed"), Fmt.rate(stats.diskReadKBs)),
                     (L.t("Tốc độ ghi", "Write speed"), Fmt.rate(stats.diskWriteKBs)),
                     (L.t("Nhiệt độ", "Temperature"), SensorsInfo.text(stats.sensors.storageTemperature))],
                    [(L.t("Model:", "Model:"), hw.diskModel),
                     (L.t("Loại:", "Type:"), hw.diskMedium),
                     (L.t("Firmware:", "Firmware:"), hw.diskRevision),
                     (L.t("Dung lượng:", "Capacity:"), Fmt.gb(hw.diskCapacity)),
                     (L.t("Còn trống:", "Free:"), Fmt.gb(stats.diskFree)),
                     (L.t("Đã dùng:", "Used:"), stats.diskTotal > 0
                        ? String(format: "%.0f%%", Double(stats.diskTotal - stats.diskFree) / Double(stats.diskTotal) * 100)
                        : "—"),
                     (L.t("Đã định dạng:", "Formatted:"), hw.diskName),
                     (L.t("Đĩa hệ thống:", "System disk:"), L.t("Có", "Yes"))])
        case .gpu:
            return ("GPU", hw.gpuName,
                    [(L.t("Mức sử dụng", "Utilization"), String(format: "%.0f%%", stats.gpu.utilization)),
                     ("Renderer", String(format: "%.0f%%", stats.gpu.renderer)),
                     ("Tiler", String(format: "%.0f%%", stats.gpu.tiler)),
                     (L.t("Bộ nhớ đang dùng", "Memory in use"), Fmt.bytesAuto(stats.gpu.inUseMemory)),
                     (L.t("Đã cấp phát", "Allocated"), Fmt.bytesAuto(stats.gpu.allocatedMemory)),
                     (L.t("Nhiệt độ", "Temperature"),
                      SensorsInfo.text(stats.gpu.temperature ?? stats.sensors.gpuTemperature)),
                     (L.t("Xung nhân", "Core clock"),
                      stats.gpu.coreClock.map { "\($0) MHz" } ?? "—")],
                    [(L.t("Tên GPU:", "GPU name:"), hw.gpuName),
                     (L.t("Số nhân GPU:", "GPU cores:"), hw.gpuCores > 0 ? "\(hw.gpuCores)" : "—"),
                     ("IOClass:", stats.gpu.ioClass.isEmpty ? "—" : stats.gpu.ioClass),
                     (L.t("Nguồn:", "Power:"), stats.gpu.poweredOn ? L.t("Bật", "On") : L.t("Tắt", "Off")),
                     (L.t("Bộ nhớ:", "Memory:"), hw.metalUnifiedMemory
                        ? L.t("Dùng chung với RAM", "Shared with RAM")
                        : L.t("Riêng", "Dedicated")),
                     (L.t("Ngân sách GPU:", "GPU budget:"), Fmt.bytesAuto(hw.metalWorkingSet)),
                     (L.t("Buffer tối đa:", "Max buffer:"), Fmt.bytesAuto(hw.metalMaxBuffer)),
                     ("Ray tracing:", hw.metalRaytracing ? L.t("Có", "Yes") : L.t("Không", "No")),
                     (L.t("Tổng RAM:", "Total RAM:"), Fmt.gb(hw.memTotal))])
        case .sensors:
            let sensors = stats.sensors
            var values: [(String, String)] = [
                (L.t("CPU", "CPU"), SensorsInfo.text(sensors.cpuTemperature)),
                ("GPU", SensorsInfo.text(sensors.gpuTemperature)),
                (L.t("Ổ lưu trữ", "Storage"), SensorsInfo.text(sensors.storageTemperature)),
                (L.t("Pin", "Battery"), SensorsInfo.text(sensors.batteryTemperature))
            ]
            for fan in sensors.fans { values.append((fan.name, fan.rpmText)) }
            var info: [(String, String)] = [
                (L.t("Số cảm biến:", "Sensors:"), "\(sensors.temperatures.count)"),
                (L.t("Số quạt:", "Fans:"), "\(sensors.fans.count)")
            ]
            for fan in sensors.fans {
                info.append(("\(fan.name) min/max:",
                             String(format: "%.0f / %.0f RPM", fan.minRPM, fan.maxRPM)))
                if fan.target > 0 {
                    info.append(("\(fan.name) " + L.t("mục tiêu:", "target:"),
                                 String(format: "%.0f RPM", fan.target)))
                }
            }
            info.append((L.t("Nguồn:", "Source:"), "AppleSMC"))
            return (L.t("Cảm biến", "Sensors"), hw.machineModel, values, info)
        case .sensors:
            let sensors = stats.sensors
            var values: [(String, String)] = [
                (L.t("CPU", "CPU"), SensorsInfo.text(sensors.cpuTemperature)),
                ("GPU", SensorsInfo.text(sensors.gpuTemperature)),
                (L.t("Ổ lưu trữ", "Storage"), SensorsInfo.text(sensors.storageTemperature)),
                (L.t("Pin", "Battery"), SensorsInfo.text(sensors.batteryTemperature))
            ]
            for fan in sensors.fans { values.append((fan.name, fan.rpmText)) }
            var info: [(String, String)] = [
                (L.t("Số cảm biến:", "Sensors:"), "\(sensors.temperatures.count)"),
                (L.t("Số quạt:", "Fans:"), "\(sensors.fans.count)")
            ]
            for fan in sensors.fans {
                info.append(("\(fan.name) min/max:",
                             String(format: "%.0f / %.0f RPM", fan.minRPM, fan.maxRPM)))
                if fan.target > 0 {
                    info.append(("\(fan.name) " + L.t("mục tiêu:", "target:"),
                                 String(format: "%.0f RPM", fan.target)))
                }
            }
            info.append((L.t("Nguồn:", "Source:"), "AppleSMC"))
            return (L.t("Cảm biến", "Sensors"), hw.machineModel, values, info)
        case .bluetooth:
            let connected = presenter.bluetoothDevices.filter { $0.connected }.count
            let controller = presenter.bluetoothController
            return ("Bluetooth", controller.chipset,
                    [(L.t("Trạng thái", "Status"), controller.powered ? L.t("Bật", "On") : L.t("Tắt", "Off")),
                     (L.t("Đã kết nối", "Connected"), "\(connected)"),
                     (L.t("Đã ghép nối", "Paired"), "\(presenter.bluetoothDevices.count)")],
                    [(L.t("Địa chỉ:", "Address:"), controller.address),
                     ("Chipset:", controller.chipset),
                     ("Firmware:", controller.firmware),
                     (L.t("Kết nối:", "Transport:"), controller.transport),
                     (L.t("Nhà sản xuất:", "Vendor:"), controller.vendor),
                     (L.t("Dịch vụ:", "Services:"), controller.services)])
        case .network:
            return (adapter.displayName, adapter.bsdName.isEmpty ? "—" : adapter.bsdName,
                    [(L.t("Gửi", "Send"), Fmt.bitrate(stats.netTxKBs)),
                     (L.t("Nhận", "Receive"), Fmt.bitrate(stats.netRxKBs)),
                     (L.t("Tổng tải lên", "Total upload"), Fmt.bytesAuto(stats.netTotalTx)),
                     (L.t("Tổng tải xuống", "Total download"), Fmt.bytesAuto(stats.netTotalRx)),
                     (L.t("Gói nhận/gửi", "Packets in/out"),
                      "\(adapter.packetsIn) / \(adapter.packetsOut)"),
                     (L.t("Lỗi nhận/gửi", "Errors in/out"),
                      "\(adapter.errorsIn) / \(adapter.errorsOut)")],
                    [(L.t("Tên bộ điều hợp:", "Adapter name:"), adapter.displayName),
                     (L.t("Trạng thái:", "Status:"), adapter.isUp ? L.t("Hoạt động", "Up") : L.t("Ngắt", "Down")),
                     (L.t("Tốc độ link:", "Link speed:"), adapter.linkSpeedText),
                     ("MTU:", adapter.mtu > 0 ? "\(adapter.mtu)" : "—"),
                     (L.t("Địa chỉ MAC:", "MAC address:"), adapter.mac),
                     (L.t("Địa chỉ IPv4:", "IPv4 address:"), adapter.ipv4),
                     (L.t("Địa chỉ IPv6:", "IPv6 address:"), adapter.ipv6),
                     (L.t("Bộ định tuyến:", "Router:"), adapter.router),
                     ("DNS:", adapter.dns)])
        }
    }

    // MARK: - Thành phần nhỏ

    private func bottom(compact: Bool,
                        values: [(String, String)],
                        info: [(String, String)]) -> some View {
        HStack(alignment: .top, spacing: 18) {
            FlowLayout(spacing: 22, lineSpacing: 12) {
                ForEach(values, id: \.0) { item in
                    stat(item.0, item.1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !compact {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(info, id: \.0) { item in
                        infoRow(item.0, item.1)
                    }
                }
                .frame(width: 240)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(W10.font(19, .light))
                .foregroundColor(W10.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(subtitle)
                .font(W10.font(12))
                .foregroundColor(W10.textDim)
                .lineLimit(1)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(W10.font(12)).foregroundColor(W10.textDim).lineLimit(1)
            Text(value).font(W10.font(20, .light)).foregroundColor(W10.text).lineLimit(1)
        }
        .fixedSize()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(W10.font(12)).foregroundColor(W10.textDim).lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(W10.font(12))
                .foregroundColor(W10.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color)
                .frame(width: 9, height: 9)
                .overlay(Rectangle().stroke(W10.memLine.opacity(0.7), lineWidth: 0.5))
            Text(label).font(W10.font(11)).foregroundColor(W10.textDim).lineLimit(1)
        }
        .fixedSize()
    }

    // MARK: - Dữ liệu đồ thị

    private func title(_ resource: PerfResource) -> String {
        switch resource {
        case .cpu:       return "CPU"
        case .memory:    return L.t("Bộ nhớ", "Memory")
        case .disk:      return L.t("Đĩa 0 (\(hw.diskName))", "Disk 0 (\(hw.diskName))")
        case .network:   return adapter.displayName
        case .gpu:       return "GPU"
        case .bluetooth: return "Bluetooth"
        case .sensors:   return L.t("Cảm biến", "Sensors")
        }
    }

    private func sidebarSubtitle(_ resource: PerfResource) -> String {
        switch resource {
        case .cpu:
            return hw.baseSpeedGHz > 0
                ? String(format: "%.0f%%  %@", stats.cpuUsage, hw.baseSpeedText)
                : String(format: "%.0f%%", stats.cpuUsage)
        case .memory:
            return String(format: "%@/%@ (%.0f%%)", Fmt.gb(stats.memUsed),
                          Fmt.gb(stats.memTotal), stats.memoryUsagePercentage)
        case .disk:
            return String(format: "%.0f%%", stats.diskActive)
        case .network:
            let send = Fmt.bitrate(stats.netTxKBs)
            let receive = Fmt.bitrate(stats.netRxKBs)
            return L.t("G: \(send)  N: \(receive)", "S: \(send)  R: \(receive)")
        case .gpu:
            return String(format: "%.0f%%  %@", stats.gpu.utilization,
                          Fmt.bytesAuto(stats.gpu.inUseMemory))
        case .bluetooth:
            let connected = presenter.bluetoothDevices.filter { $0.connected }.count
            return L.t("\(connected) thiết bị kết nối", "\(connected) devices connected")
        case .sensors:
            let cpu = SensorsInfo.text(stats.sensors.cpuTemperature)
            let fan = stats.sensors.fans.first.map { String(format: "%.0f RPM", $0.rpm) } ?? "—"
            return "\(cpu)  \(fan)"
        }
    }

    private func lineColor(_ resource: PerfResource) -> Color {
        switch resource {
        case .cpu:     return W10.cpuLine
        case .memory:  return W10.memLine
        case .disk:    return W10.diskLine
        case .network: return W10.netLine
        case .gpu:     return W10.gpuLine
        case .bluetooth: return W10.btLine
        case .sensors: return Color(rgb: 0xC0392B)
        }
    }

    private func series(for resource: PerfResource, fillOnly: Bool = false) -> W10Series {
        let samples: [Double]
        let line: Color
        let fill: Color
        switch resource {
        case .cpu:
            samples = presenter.cpuHistory
            line = W10.cpuLine
            fill = W10.cpuFill
        case .memory:
            samples = presenter.memHistory
            line = W10.memLine
            fill = W10.memFill
        case .disk:
            samples = presenter.diskHistory
            line = W10.diskLine
            fill = W10.diskFill
        case .network:
            let scale = max(presenter.netScaleMbps, 0.1)
            samples = presenter.netHistory.map { $0 / scale }
            line = W10.netLine
            fill = W10.netFill
        case .gpu:
            samples = presenter.gpuHistory
            line = W10.gpuLine
            fill = W10.gpuFill
        case .bluetooth:
            samples = []
            line = W10.btLine
            fill = W10.btFill
        case .sensors:
            samples = presenter.tempHistory
            line = Color(rgb: 0xC0392B)
            fill = Color(rgb: 0xF5D0CC)
        }
        return W10Series(samples: samples, line: line, fill: fill.opacity(fillOnly ? 0.85 : 1))
    }
}
