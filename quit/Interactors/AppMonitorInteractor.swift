import AppKit
import IOKit
import Darwin

/// Tốc độ cập nhật, giống menu View ▸ Update speed của Task Manager.
enum UpdateSpeed: String, CaseIterable, Identifiable {
    case high, normal, low, paused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high:   return L.t("Cao", "High")
        case .normal: return L.t("Bình thường", "Normal")
        case .low:    return L.t("Thấp", "Low")
        case .paused: return L.t("Đã tạm dừng", "Paused")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .high:   return 1.0
        case .normal: return 2.0
        case .low:    return 4.0
        case .paused: return nil
        }
    }
}

protocol AppMonitorInteractorOutput: AnyObject {
    func interactorDidUpdate(entities: [AppEntity], stats: SystemStats)
    func interactorDidSampleStats(_ stats: SystemStats)
}

class AppMonitorInteractor {
    weak var output: AppMonitorInteractorOutput?

    private var procTimer: Timer?
    private var sampleTimer: Timer?
    private var speed: UpdateSpeed = .normal

    private let fetchQueue = DispatchQueue(label: "com.utc.quit.fetch", qos: .userInitiated)
    private let machNsRatio: Double

    // MARK: Trạng thái mẫu trước (chỉ truy cập trên fetchQueue)
    private var lastCpuTimeMap: [Int32: UInt64] = [:]
    private var lastNetTcpMap: [Int32: (rx: UInt64, tx: UInt64)] = [:]
    private var lastDiskIOMap: [Int32: (read: UInt64, write: UInt64)] = [:]
    private var lastGPUTimeMap: [Int32: UInt64] = [:]
    private var lastProcSampleTime = Date()

    private var lastSysNetRx: UInt64 = 0
    private var lastSysNetTx: UInt64 = 0
    private var lastDiskRead: UInt64 = 0
    private var lastDiskWrite: UInt64 = 0
    private var lastDiskBusyNs: UInt64 = 0
    private var lastCpuTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var lastCoreTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
    private var lastSysSampleTime = Date()
    private var primaryInterface = ""
    private var primaryInterfaceAge = 0

    private var pathCache: [Int32: String] = [:]
    private var userCache: [Int32: String] = [:]
    private var uidNameCache: [UInt32: String] = [:]

    private var stats = SystemStats()
    private let gpuReader = GPUReader()
    private let smcReader = SMCReader()

    init() {
        var tbInfo = mach_timebase_info_data_t()
        mach_timebase_info(&tbInfo)
        machNsRatio = Double(tbInfo.numer) / Double(tbInfo.denom)
        stats.memTotal = HardwareInfo.current.memTotal
    }

    // MARK: - Vòng lặp

    func start() {
        fetchQueue.async { [weak self] in
            self?.sampleSystem(emit: false)
            self?.fetchData()
        }
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.speed != .paused else { return }
            self.fetchQueue.async { self.sampleSystem(emit: true) }
        }
        restartProcTimer()
    }

    func refresh() {
        fetchQueue.async { [weak self] in
            self?.sampleSystem(emit: true)
            self?.fetchData()
        }
    }

    func setSpeed(_ newSpeed: UpdateSpeed) {
        speed = newSpeed
        restartProcTimer()
    }

    private func restartProcTimer() {
        procTimer?.invalidate()
        procTimer = nil
        guard let interval = speed.interval else { return }
        procTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.fetchQueue.async { self.fetchData() }
        }
    }

    // MARK: - Lấy mẫu hệ thống (nhẹ, 1 giây/lần)

    private func sampleSystem(emit: Bool) {
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastSysSampleTime), 0.001)

        // CPU toàn hệ thống
        if let ticks = cpuTicks() {
            if let last = lastCpuTicks {
                let dUser = Double(ticks.user &- last.user)
                let dSys = Double(ticks.system &- last.system)
                let dNice = Double(ticks.nice &- last.nice)
                let dIdle = Double(ticks.idle &- last.idle)
                let total = dUser + dSys + dNice + dIdle
                if total > 0 {
                    // Giống Stats: tổng = user + system (nice nằm trong tổng tick
                    // nhưng không cộng vào mức sử dụng).
                    stats.cpuUsage = min(((dUser + dSys) / total) * 100.0, 100.0)
                    stats.cpuSystemUsage = min((dSys / total) * 100.0, 100.0)
                }
            }
            lastCpuTicks = ticks
        }
        stats.perCore = perCoreUsage()
        applyClusterUsage()
        stats.gpu = gpuReader.read()
        stats.sensors = smcReader.read()

        // Bộ nhớ
        applyMemoryStats()

        // Mạng: chỉ đếm interface chính, giống Stats. Cộng hết mọi interface sẽ
        // đếm trùng khi có VPN/utun hoặc nhiều card mạng.
        if primaryInterface.isEmpty || primaryInterfaceAge >= 10 {
            primaryInterface = NetworkAdapterInfo.current().bsdName
            primaryInterfaceAge = 0
        }
        primaryInterfaceAge += 1

        let (sysRx, sysTx) = systemNetworkBytes(interface: primaryInterface)
        if lastSysNetRx > 0 || lastSysNetTx > 0 {
            var deltaRx = sysRx >= lastSysNetRx ? sysRx - lastSysNetRx : 0
            var deltaTx = sysTx >= lastSysNetTx ? sysTx - lastSysNetTx : 0
            // Bộ đếm bị reset khi đổi mạng sẽ tạo ra cú nhảy khổng lồ — bỏ mẫu đó.
            let maxDelta = UInt64(10_000_000_000.0 / 8.0 * 1.5 * elapsed)
            if deltaRx > maxDelta { deltaRx = 0 }
            if deltaTx > maxDelta { deltaTx = 0 }
            stats.netRxKBs = Double(deltaRx) / elapsed / 1024
            stats.netTxKBs = Double(deltaTx) / elapsed / 1024
            stats.netTotalRx += deltaRx
            stats.netTotalTx += deltaTx
        }
        lastSysNetRx = sysRx
        lastSysNetTx = sysTx

        // Đĩa
        let disk = diskCounters()
        if lastDiskRead > 0 || lastDiskWrite > 0 {
            stats.diskReadKBs = disk.read >= lastDiskRead ? Double(disk.read - lastDiskRead) / elapsed / 1024 : 0
            stats.diskWriteKBs = disk.write >= lastDiskWrite ? Double(disk.write - lastDiskWrite) / elapsed / 1024 : 0
            let busy = disk.busyNs >= lastDiskBusyNs ? Double(disk.busyNs - lastDiskBusyNs) : 0
            stats.diskActive = min(busy / (elapsed * 1_000_000_000.0) * 100.0, 100.0)
        }
        lastDiskRead = disk.read
        lastDiskWrite = disk.write
        lastDiskBusyNs = disk.busyNs

        var fs = statfs()
        if statfs("/", &fs) == 0 {
            stats.diskTotal = UInt64(fs.f_blocks) * UInt64(fs.f_bsize)
            stats.diskFree = UInt64(fs.f_bavail) * UInt64(fs.f_bsize)
        }

        stats.uptime = Date().timeIntervalSince(HardwareInfo.current.bootTime)
        lastSysSampleTime = now

        guard emit else { return }
        let snapshot = stats
        DispatchQueue.main.async { self.output?.interactorDidSampleStats(snapshot) }
    }

    // MARK: - Quét tiến trình

    private func fetchData() {
        let nsApps = NSWorkspace.shared.runningApplications
        let nsAppsMap = Dictionary(
            nsApps.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastProcSampleTime), 0.001)
        let nettopMap = fetchNettopData()
        let gpuTimeMap = gpuReader.readProcessGPUTime()
        let psMap = fetchPSData()

        var rawPids = [Int32](repeating: 0, count: 8192)
        let pidCount = Int(proc_listallpids(&rawPids, Int32(MemoryLayout<Int32>.size * rawPids.count)))
        let livePids = rawPids.prefix(max(pidCount, 0)).filter { $0 > 0 }
        let liveSet = Set(livePids)

        var newCpuTimeMap: [Int32: UInt64] = [:]
        var newNetTcpMap: [Int32: (rx: UInt64, tx: UInt64)] = [:]
        var newDiskIOMap: [Int32: (read: UInt64, write: UInt64)] = [:]
        var newGPUTimeMap: [Int32: UInt64] = [:]
        var entities: [AppEntity] = []
        var totalThreads = 0
        var totalHandles = 0

        let coreCount = Double(ProcessInfo.processInfo.processorCount)

        for pid in livePids {
            var usage = rusage(pid: pid)
            let nsApp = nsAppsMap[pid]

            let path: String
            if let cached = pathCache[pid] {
                path = cached
            } else {
                path = executablePath(pid: pid)
                pathCache[pid] = path
            }

            let name: String
            if let localizedName = nsApp?.localizedName, !localizedName.isEmpty {
                name = localizedName
            } else if !path.isEmpty {
                name = URL(fileURLWithPath: path).lastPathComponent
            } else {
                name = processName(pid: pid)
            }
            if name.isEmpty && usage.memory == 0 { continue }

            // CPU
            var task = taskInfo(pid: pid)
            let currentCpuTime = task.cpuTime
            newCpuTimeMap[pid] = currentCpuTime
            var cpu = 0.0
            if let lastTime = lastCpuTimeMap[pid], currentCpuTime >= lastTime {
                let deltaNs = Double(currentCpuTime - lastTime) * machNsRatio
                cpu = min((deltaNs / (elapsed * 1_000_000_000.0 * coreCount)) * 100.0, 100.0)
            }

            // Mạng
            let curRx = nettopMap[pid]?.rx ?? 0
            let curTx = nettopMap[pid]?.tx ?? 0
            newNetTcpMap[pid] = (curRx, curTx)
            var netRx = 0.0
            var netTx = 0.0
            if let last = lastNetTcpMap[pid], curRx >= last.rx, curTx >= last.tx {
                netRx = Double(curRx - last.rx) / elapsed / 1024
                netTx = Double(curTx - last.tx) / elapsed / 1024
            }

            // Đĩa
            newDiskIOMap[pid] = (usage.diskRead, usage.diskWrite)
            var diskRead = 0.0
            var diskWrite = 0.0
            if let last = lastDiskIOMap[pid], usage.diskRead >= last.read, usage.diskWrite >= last.write {
                diskRead = Double(usage.diskRead - last.read) / elapsed / 1024
                diskWrite = Double(usage.diskWrite - last.write) / elapsed / 1024
            }

            // GPU
            let gpuTime = gpuTimeMap[pid] ?? 0
            if gpuTime > 0 { newGPUTimeMap[pid] = gpuTime }
            var gpu = 0.0
            if let last = lastGPUTimeMap[pid], gpuTime >= last {
                gpu = min(Double(gpuTime - last) / (elapsed * 1_000_000_000.0) * 100.0, 100.0)
            }

            let handles = handleCount(pid: pid)

            // proc_pid_rusage / proc_pidinfo bị từ chối với tiến trình của user khác
            // (WindowServer, kernel_task...) nên rơi về `ps`, giống cách Stats làm.
            // Lưu ý: %CPU của ps là trung bình suy giảm, không phải mẫu tức thời.
            if usage.memory == 0, task.threads == 0, let fallback = psMap[pid] {
                usage.memory = fallback.rssKB / 1024.0
                cpu = min(fallback.cpu / coreCount, 100.0)
            }

            totalThreads += task.threads
            totalHandles += handles

            let bsd = bsdInfo(pid: pid)
            let user: String
            if let cached = userCache[pid] {
                user = cached
            } else {
                user = bsd.user
                userCache[pid] = user
            }

            entities.append(AppEntity(
                id: pid,
                ppid: bsd.ppid,
                name: name,
                path: path,
                memory: usage.memory,
                cpu: cpu,
                netRxKBs: netRx,
                netTxKBs: netTx,
                diskReadKBs: diskRead,
                diskWriteKBs: diskWrite,
                gpu: gpu,
                threads: task.threads,
                handles: handles,
                cpuTime: Double(currentCpuTime) * machNsRatio / 1_000_000_000.0,
                netRxBytes: curRx,
                netTxBytes: curTx,
                category: AppEntity.categorize(path: path, app: nsApp),
                user: user,
                runningApp: nsApp
            ))
        }

        lastCpuTimeMap = newCpuTimeMap
        lastNetTcpMap = newNetTcpMap
        lastDiskIOMap = newDiskIOMap
        lastGPUTimeMap = newGPUTimeMap
        lastProcSampleTime = now
        pathCache = pathCache.filter { liveSet.contains($0.key) }
        userCache = userCache.filter { liveSet.contains($0.key) }

        stats.processCount = entities.count
        stats.threadCount = totalThreads
        stats.handleCount = totalHandles

        let snapshot = stats
        DispatchQueue.main.async {
            self.output?.interactorDidUpdate(entities: entities, stats: snapshot)
        }
    }

    // MARK: - Trợ giúp tiến trình

    private func processName(pid: Int32) -> String {
        var name = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &name, UInt32(name.count)) > 0 { return String(cString: name) }
        return "pid:\(pid)"
    }

    private func executablePath(pid: Int32) -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 { return String(cString: path) }
        return ""
    }

    private func rusage(pid: Int32) -> (memory: Double, diskRead: UInt64, diskWrite: UInt64) {
        var info = rusage_info_v4()
        let res = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutablePointer($0))
            }
        }
        guard res == 0 else { return (0, 0, 0) }
        return (Double(info.ri_phys_footprint) / 1_048_576.0,
                info.ri_diskio_bytesread,
                info.ri_diskio_byteswritten)
    }

    private func taskInfo(pid: Int32) -> (cpuTime: UInt64, threads: Int) {
        var info = proc_taskinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        guard ret > 0 else { return (0, 0) }
        return (info.pti_total_user + info.pti_total_system, Int(info.pti_threadnum))
    }

    /// Tương đương "Handles" của Windows: số bộ mô tả tệp đang mở.
    private func handleCount(pid: Int32) -> Int {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return 0 }
        return Int(size) / MemoryLayout<proc_fdinfo>.stride
    }

    private func bsdInfo(pid: Int32) -> (user: String, ppid: Int32) {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard ret > 0 else { return ("", 0) }
        let ppid = Int32(bitPattern: info.pbi_ppid)
        if let cached = uidNameCache[info.pbi_uid] { return (cached, ppid) }
        var name = "uid \(info.pbi_uid)"
        if let pw = getpwuid(info.pbi_uid), let raw = pw.pointee.pw_name {
            name = String(cString: raw)
        }
        uidNameCache[info.pbi_uid] = name
        return (name, ppid)
    }

    // MARK: - Trợ giúp hệ thống

    private func cpuTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1),
                UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
    }

    /// Mức sử dụng từng lõi logic, cho chế độ xem "Bộ xử lý logic".
    private func perCoreUsage() -> [Double] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return stats.perCore }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var usage: [Double] = []
        var newTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
        for index in 0..<Int(cpuCount) {
            let base = index * Int(CPU_STATE_MAX)
            let ticks = (user: UInt64(info[base + Int(CPU_STATE_USER)]),
                         system: UInt64(info[base + Int(CPU_STATE_SYSTEM)]),
                         idle: UInt64(info[base + Int(CPU_STATE_IDLE)]),
                         nice: UInt64(info[base + Int(CPU_STATE_NICE)]))
            newTicks.append(ticks)
            if index < lastCoreTicks.count {
                let last = lastCoreTicks[index]
                let dUser = Double(ticks.user &- last.user)
                let dSys = Double(ticks.system &- last.system)
                let dNice = Double(ticks.nice &- last.nice)
                let dIdle = Double(ticks.idle &- last.idle)
                let total = dUser + dSys + dNice + dIdle
                usage.append(total > 0 ? min(((total - dIdle) / total) * 100.0, 100.0) : 0)
            } else {
                usage.append(0)
            }
        }
        lastCoreTicks = newTicks
        return usage
    }

    /// Trung bình mức dùng theo cụm lõi hiệu năng (P) và tiết kiệm điện (E).
    private func applyClusterUsage() {
        let clusters = HardwareInfo.current.coreClusters
        guard clusters.count == stats.perCore.count, !clusters.isEmpty else {
            stats.efficiencyUsage = 0
            stats.performanceUsage = stats.cpuUsage
            return
        }
        var eSum = 0.0, eCount = 0.0, pSum = 0.0, pCount = 0.0
        for (index, cluster) in clusters.enumerated() {
            if cluster == "E" { eSum += stats.perCore[index]; eCount += 1 }
            else { pSum += stats.perCore[index]; pCount += 1 }
        }
        stats.efficiencyUsage = eCount > 0 ? eSum / eCount : 0
        stats.performanceUsage = pCount > 0 ? pSum / pCount : 0
    }

    private func applyMemoryStats() {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page = Double(vm_kernel_page_size)
        let active = Double(vmStats.active_count) * page
        let inactive = Double(vmStats.inactive_count) * page
        let speculative = Double(vmStats.speculative_count) * page
        let wired = Double(vmStats.wire_count) * page
        let compressed = Double(vmStats.compressor_page_count) * page
        let purgeable = Double(vmStats.purgeable_count) * page
        let external = Double(vmStats.external_page_count) * page

        // Cùng công thức với exelban/Stats và Activity Monitor: bộ nhớ "đang dùng"
        // không tính phần file-backed (external) và phần có thể thu hồi (purgeable).
        let total = Double(HardwareInfo.current.memTotal)
        let used = max(active + inactive + speculative + wired + compressed - purgeable - external, 0)
        let free = max(total - used, 0)

        stats.memTotal = HardwareInfo.current.memTotal
        stats.memUsed = UInt64(min(used, total))
        stats.memAvailable = UInt64(free)
        stats.memCached = UInt64(purgeable + external)
        stats.memCompressed = UInt64(compressed)
        stats.memWired = UInt64(wired)
        stats.memApp = UInt64(max(used - wired - compressed, 0))
        stats.memoryUsagePercentage = total > 0 ? used / total * 100.0 : 0

        // `vm.memory_pressure` không tồn tại trên macOS hiện tại (luôn trả 0).
        // Stats dùng khoá này: 1 = bình thường, 2 = cảnh báo, 4 = nguy cấp.
        var pressure: Int = 0
        var psize = MemoryLayout<UInt32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &psize, nil, 0)
        stats.memoryPressure = pressure

        var swap = xsw_usage()
        var ssize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &ssize, nil, 0) == 0 {
            stats.swapUsed = swap.xsu_used
            stats.swapTotal = swap.xsu_total
        }
    }

    /// Byte của một interface; truyền rỗng thì cộng mọi interface (trừ loopback).
    private func systemNetworkBytes(interface: String) -> (rx: UInt64, tx: UInt64) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        defer { freeifaddrs(first) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr = Optional(first)
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            let matches = interface.isEmpty ? !name.hasPrefix("lo") : name == interface
            if matches,
               addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = addr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }
            ptr = addr.pointee.ifa_next
        }
        return (rx, tx)
    }

    private func diskCounters() -> (read: UInt64, write: UInt64, busyNs: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var busy: UInt64 = 0
        var drive = IOIteratorNext(iterator)
        while drive != 0 {
            if let props = IORegistryEntryCreateCFProperty(drive, "Statistics" as CFString,
                                                            kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (props["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (props["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                busy += (props["Total Time (Read)"] as? NSNumber)?.uint64Value ?? 0
                busy += (props["Total Time (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(drive)
            drive = IOIteratorNext(iterator)
        }
        return (read, write, busy)
    }

    /// `ps -A -o pid=,pcpu=,rss=` — nguồn duy nhất lấy được CPU/RSS của tiến trình
    /// thuộc user khác mà không cần quyền root (~20ms).
    private func fetchPSData() -> [Int32: (cpu: Double, rssKB: Double)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-o", "pid=,pcpu=,rss="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: (cpu: Double, rssKB: Double)] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rss = Double(parts[2]) else { continue }
            result[pid] = (cpu, rss)
        }
        return result
    }

    // MARK: - nettop

    private func fetchNettopData() -> [Int32: (rx: UInt64, tx: UInt64)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-l", "1", "-x", "-P", "-n"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        return parseNettopOutput(output)
    }

    private func parseNettopOutput(_ output: String) -> [Int32: (rx: UInt64, tx: UInt64)] {
        var result: [Int32: (rx: UInt64, tx: UInt64)] = [:]
        let timestampLen = 16

        for line in output.components(separatedBy: "\n") {
            guard line.count > timestampLen, line.first?.isNumber == true else { continue }

            let rest = line[line.index(line.startIndex, offsetBy: timestampLen)...]

            var nameEnd = rest.startIndex
            var spaceRun = 0
            for idx in rest.indices {
                let ch = rest[idx]
                if ch == " " {
                    spaceRun += 1
                    if spaceRun >= 2 { break }
                } else {
                    spaceRun = 0
                    nameEnd = rest.index(after: idx)
                }
            }

            let procField = String(rest[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            guard let lastDot = procField.lastIndex(of: "."),
                  let pid = Int32(procField[procField.index(after: lastDot)...]) else { continue }

            let afterName = rest[nameEnd...]
            var parts = [Substring]()
            for token in afterName.split(separator: " ", omittingEmptySubsequences: true) {
                parts.append(token)
                if parts.count == 2 { break }
            }
            guard parts.count == 2 else { continue }

            let rx = UInt64(parts[0]) ?? 0
            let tx = UInt64(parts[1]) ?? 0
            if let existing = result[pid] {
                result[pid] = (existing.rx + rx, existing.tx + tx)
            } else {
                result[pid] = (rx, tx)
            }
        }
        return result
    }
}
