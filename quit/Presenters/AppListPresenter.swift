import SwiftUI
import Observation

enum ProcSortKey: String {
    case name, status, cpu, memory, disk, network, gpu, pid, user, threads, handles, cpuTime, netTotal
}

/// Cây tiến trình: mỗi ứng dụng là một hàng cha cộng gộp, các tiến trình con
/// (helper, renderer...) nằm lồng bên dưới — giống nhóm ứng dụng của Task Manager.
struct ProcessTree {
    var roots: [AppEntity] = []
    var childrenByRoot: [Int32: [AppEntity]] = [:]
    var background: [AppEntity] = []
    var system: [AppEntity] = []
}

@Observable
class AppListPresenter: AppMonitorInteractorOutput {
    private(set) var rawEntities: [AppEntity] = []
    private(set) var tree = ProcessTree()
    var systemStats = SystemStats()
    var sortOrder = [KeyPathComparator(\AppEntity.memory, order: .reverse)]

    var updateSpeed: UpdateSpeed = .normal {
        didSet { interactor.setSpeed(updateSpeed) }
    }

    // Lịch sử cho đồ thị 60 giây
    static let historyCapacity = 60
    private(set) var cpuHistory: [Double] = []      // 0...1
    private(set) var cpuKernelHistory: [Double] = [] // 0...1
    private(set) var perCoreHistory: [[Double]] = [] // mỗi lõi một mảng 0...1
    private(set) var gpuHistory: [Double] = []       // 0...1
    private(set) var tempHistory: [Double] = []      // nhiệt độ CPU / 110°C

    private(set) var bluetoothController = BluetoothController()
    private(set) var bluetoothDevices: [BluetoothDeviceInfo] = []
    private let bluetoothReader = BluetoothReader()
    private(set) var memHistory: [Double] = []      // 0...1
    private(set) var diskHistory: [Double] = []     // 0...1
    private(set) var diskReadHistory: [Double] = []  // KB/s
    private(set) var diskWriteHistory: [Double] = [] // KB/s
    private(set) var netHistory: [Double] = []      // Mbps
    private(set) var netRxHistory: [Double] = []    // Mbps
    private(set) var netTxHistory: [Double] = []    // Mbps

    /// Tab Lịch sử ứng dụng cộng dồn phần **phát sinh thêm sau mỗi nhịp**, chứ
    /// không lấy "tổng hiện tại trừ mốc". Tổng hiện tại của một nhóm sẽ tụt khi
    /// một tiến trình con thoát (Chrome đóng tab), kiểu trừ mốc sẽ làm số nhảy lùi
    /// rồi kẹt ở 0; cộng dồn delta thì phần đã tiêu không bao giờ mất.
    private var usageTotals: [String: AppTotals] = [:]
    private var lastSeenTotals: [String: AppTotals] = [:]
    private(set) var usageSince = Date()

    struct AppTotals {
        var cpu: Double = 0
        var rx: UInt64 = 0
        var tx: UInt64 = 0
    }

    private let interactor: AppMonitorInteractor

    init(interactor: AppMonitorInteractor = AppMonitorInteractor()) {
        self.interactor = interactor
        interactor.output = self
        interactor.start()
    }

    // MARK: - Truy vấn

    var appEntities: [AppEntity] { rawEntities.sorted(using: sortOrder) }
    /// Ứng dụng người dùng đang mở: đúng nhóm "Ứng dụng" của tab Tiến trình —
    /// chỉ app có giao diện (`activationPolicy == .regular`) và đã cộng gộp tiến
    /// trình con, nên số liệu khớp với cửa sổ Task Manager.
    var openApps: [AppEntity] {
        tree.roots.sorted { $0.memory > $1.memory }
    }


    func entities(in category: ProcessCategory) -> [AppEntity] {
        rawEntities.filter { $0.category == category }
    }

    var totalCPU: Double { min(systemStats.cpuUsage, 100) }

    /// Thang đo động cho đồ thị mạng, giống Task Manager (100 Kbps, 1 Mbps, 10 Mbps...).
    /// Thang đo động cho đồ thị tốc độ đĩa.
    var diskScaleKBs: Double {
        let peak = max(diskReadHistory.max() ?? 0, diskWriteHistory.max() ?? 0)
        let steps: [Double] = [100, 512, 1024, 5120, 10240, 51200, 102400, 512000, 1024000]
        return steps.first { $0 >= peak } ?? 1024000
    }

    var netScaleMbps: Double {
        let peak = netHistory.max() ?? 0
        let steps: [Double] = [0.1, 0.5, 1, 5, 10, 50, 100, 250, 500, 1000, 2500, 10000]
        return steps.first { $0 >= peak } ?? 10000
    }

    // MARK: - Hành động

    func refresh() {
        interactor.refresh()
        refreshBluetooth()
    }

    /// system_profiler khá chậm nên chỉ đọc khi mở ngăn Bluetooth hoặc bấm làm mới.
    func refreshBluetooth() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.bluetoothReader.read()
            DispatchQueue.main.async {
                self.bluetoothController = result.controller
                self.bluetoothDevices = result.devices
            }
        }
    }

    func forceQuit(_ entity: AppEntity) {
        if let app = entity.runningApp {
            app.forceTerminate()
        } else {
            kill(entity.id, SIGKILL)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.interactor.refresh() }
    }

    func revealInFinder(_ entity: AppEntity) {
        guard !entity.path.isEmpty else { return }
        NSWorkspace.shared.selectFile(entity.path, inFileViewerRootedAtPath: "")
    }

    func activate(_ entity: AppEntity) {
        entity.runningApp?.activate(options: [.activateAllWindows])
    }

    // MARK: - Lịch sử ứng dụng

    struct AppUsage: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
        let cpuTime: Double
        let netIn: UInt64
        let netOut: UInt64

        var network: UInt64 { netIn + netOut }
    }

    var appUsage: [AppUsage] {
        var names: [String: (name: String, icon: NSImage?)] = [:]
        for entity in rawEntities where entity.isGUIApp {
            if names[Self.key(for: entity)] == nil {
                names[Self.key(for: entity)] = (entity.name, entity.icon)
            }
        }
        // Chỉ liệt kê app còn đang chạy, nhưng lấy số đã cộng dồn.
        return names.map { key, label in
            let total = usageTotals[key] ?? AppTotals()
            return AppUsage(id: key, name: label.name, icon: label.icon,
                            cpuTime: total.cpu, netIn: total.rx, netOut: total.tx)
        }
        .sorted { $0.cpuTime > $1.cpuTime }
    }

    func clearUsageHistory() {
        usageTotals.removeAll()
        usageSince = Date()
    }

    private static func key(for entity: AppEntity) -> String {
        entity.runningApp?.bundleIdentifier ?? entity.name
    }

    /// Cộng phần tăng thêm của nhịp này vào bảng tích luỹ.
    ///
    /// Nhóm mới thấy lần đầu chỉ được ghi mốc, không cộng — nếu không thì ngay
    /// nhịp đầu sau khi bật app, toàn bộ thời gian CPU từ đời trước của mọi tiến
    /// trình sẽ đổ hết vào bảng.
    private func accumulateUsage() {
        let owners = ownerKeys()
        var current: [String: AppTotals] = [:]
        for entity in rawEntities {
            guard let key = owners[entity.id] else { continue }
            var total = current[key] ?? AppTotals()
            total.cpu += entity.cpuTime
            total.rx += entity.netRxBytes
            total.tx += entity.netTxBytes
            current[key] = total
        }

        for (key, total) in current {
            guard let last = lastSeenTotals[key] else { continue }
            var acc = usageTotals[key] ?? AppTotals()
            if total.cpu > last.cpu { acc.cpu += total.cpu - last.cpu }
            if total.rx > last.rx { acc.rx += total.rx - last.rx }
            if total.tx > last.tx { acc.tx += total.tx - last.tx }
            usageTotals[key] = acc
        }
        lastSeenTotals = current
    }

    /// pid -> ứng dụng GUI sở hữu nó, tìm bằng cách leo ngược chuỗi ppid.
    ///
    /// Bắt buộc phải leo, vì tiến trình ôm socket thường KHÔNG phải tiến trình có
    /// giao diện: toàn bộ lưu lượng của Chrome nằm ở "Google Chrome Helper", mà
    /// helper thì không có `NSRunningApplication` nên lọc theo `isGUIApp` sẽ mất
    /// sạch. Tiến trình không truy được về app GUI nào (daemon hệ thống) bị bỏ qua.
    private func ownerKeys() -> [Int32: String] {
        let byPid = Dictionary(rawEntities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var owners: [Int32: String] = [:]
        var orphans = Set<Int32>()

        for entity in rawEntities {
            guard owners[entity.id] == nil, !orphans.contains(entity.id) else { continue }
            var chain: [Int32] = []
            var node: AppEntity? = entity
            var found: String?

            // Chặn số bước: chuỗi ppid hỏng (pid bị dùng lại) có thể tạo vòng lặp.
            var hops = 0
            while let current = node, hops < 64 {
                if let cached = owners[current.id] { found = cached; break }
                if orphans.contains(current.id) { break }
                if current.isGUIApp { found = Self.key(for: current); break }
                chain.append(current.id)
                node = current.ppid > 0 ? byPid[current.ppid] : nil
                hops += 1
            }

            if let found {
                owners[entity.id] = found
                for pid in chain { owners[pid] = found }
            } else {
                orphans.insert(entity.id)
                for pid in chain { orphans.insert(pid) }
            }
        }
        return owners
    }

    // MARK: - Output

    func interactorDidUpdate(entities: [AppEntity], stats: SystemStats) {
        rawEntities = entities
        tree = Self.buildTree(entities)
        systemStats = stats

        accumulateUsage()
    }

    private static func buildTree(_ entities: [AppEntity]) -> ProcessTree {
        var byParent: [Int32: [AppEntity]] = [:]
        for entity in entities where entity.ppid > 0 {
            byParent[entity.ppid, default: []].append(entity)
        }
        let appEntities = entities.filter { $0.category == .app }
        let rootIDs = Set(appEntities.map { $0.id })

        var claimed = Set<Int32>()
        var childrenByRoot: [Int32: [AppEntity]] = [:]
        for root in appEntities {
            var stack = byParent[root.id] ?? []
            var collected: [AppEntity] = []
            while let child = stack.popLast() {
                if rootIDs.contains(child.id) || claimed.contains(child.id) { continue }
                claimed.insert(child.id)
                collected.append(child)
                stack.append(contentsOf: byParent[child.id] ?? [])
            }
            childrenByRoot[root.id] = collected
        }

        let roots = appEntities.map { aggregate($0, with: childrenByRoot[$0.id] ?? []) }
        let rest = entities.filter { !claimed.contains($0.id) && $0.category != .app }
        return ProcessTree(roots: roots,
                           childrenByRoot: childrenByRoot,
                           background: rest.filter { $0.category == .background },
                           system: rest.filter { $0.category == .system })
    }

    /// Hàng cha hiển thị tổng của cả nhóm, như Task Manager khi nhóm đang thu gọn.
    private static func aggregate(_ root: AppEntity, with children: [AppEntity]) -> AppEntity {
        guard !children.isEmpty else { return root }
        let group = [root] + children
        return AppEntity(
            id: root.id,
            ppid: root.ppid,
            name: root.name,
            path: root.path,
            memory: group.reduce(0) { $0 + $1.memory },
            cpu: min(group.reduce(0) { $0 + $1.cpu }, 100),
            netRxKBs: group.reduce(0) { $0 + $1.netRxKBs },
            netTxKBs: group.reduce(0) { $0 + $1.netTxKBs },
            diskReadKBs: group.reduce(0) { $0 + $1.diskReadKBs },
            diskWriteKBs: group.reduce(0) { $0 + $1.diskWriteKBs },
            gpu: min(group.reduce(0) { $0 + $1.gpu }, 100),
            threads: group.reduce(0) { $0 + $1.threads },
            handles: group.reduce(0) { $0 + $1.handles },
            cpuTime: group.reduce(0) { $0 + $1.cpuTime },
            netRxBytes: group.reduce(0) { $0 + $1.netRxBytes },
            netTxBytes: group.reduce(0) { $0 + $1.netTxBytes },
            category: root.category,
            user: root.user,
            runningApp: root.runningApp
        )
    }

    func interactorDidSampleStats(_ stats: SystemStats) {
        systemStats = stats
        append(&cpuHistory, stats.cpuUsage / 100.0)
        append(&gpuHistory, stats.gpu.utilization / 100.0)
        append(&tempHistory, (stats.sensors.cpuTemperature ?? 0) / 110.0)
        append(&cpuKernelHistory, stats.cpuSystemUsage / 100.0)
        if perCoreHistory.count != stats.perCore.count {
            perCoreHistory = Array(repeating: [], count: stats.perCore.count)
        }
        for (index, value) in stats.perCore.enumerated() {
            append(&perCoreHistory[index], value / 100.0)
        }
        append(&memHistory, stats.memTotal > 0 ? Double(stats.memUsed) / Double(stats.memTotal) : 0)
        append(&diskHistory, stats.diskActive / 100.0)
        append(&diskReadHistory, stats.diskReadKBs)
        append(&diskWriteHistory, stats.diskWriteKBs)
        append(&netHistory, stats.netMbps)
        append(&netRxHistory, stats.netRxKBs * 8.0 / 1000.0)
        append(&netTxHistory, stats.netTxKBs * 8.0 / 1000.0)
    }

    private func append(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value.isFinite ? value : 0)
        if buffer.count > Self.historyCapacity {
            buffer.removeFirst(buffer.count - Self.historyCapacity)
        }
    }
}

extension AppEntity {
    static func sorted(_ list: [AppEntity], key: ProcSortKey, ascending: Bool) -> [AppEntity] {
        let sorted: [AppEntity]
        switch key {
        case .name:
            sorted = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .status:
            sorted = list.sorted { ($0.isSuspended ? 1 : 0, $0.name) < ($1.isSuspended ? 1 : 0, $1.name) }
        case .cpu:      sorted = list.sorted { $0.cpu < $1.cpu }
        case .memory:   sorted = list.sorted { $0.memory < $1.memory }
        case .disk:     sorted = list.sorted { $0.diskKBs < $1.diskKBs }
        case .network:  sorted = list.sorted { $0.netMbps < $1.netMbps }
        case .gpu:      sorted = list.sorted { $0.gpu < $1.gpu }
        case .pid:      sorted = list.sorted { $0.id < $1.id }
        case .user:     sorted = list.sorted { ($0.user, $0.name) < ($1.user, $1.name) }
        case .threads:  sorted = list.sorted { $0.threads < $1.threads }
        case .handles:  sorted = list.sorted { $0.handles < $1.handles }
        case .cpuTime:  sorted = list.sorted { $0.cpuTime < $1.cpuTime }
        case .netTotal: sorted = list.sorted { $0.netTotalBytes < $1.netTotalBytes }
        }
        return ascending ? sorted : sorted.reversed()
    }
}
