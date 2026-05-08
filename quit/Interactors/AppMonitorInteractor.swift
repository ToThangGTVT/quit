import AppKit

protocol AppMonitorInteractorOutput: AnyObject {
    func interactorDidUpdate(
        apps: [NSRunningApplication],
        memoryMap: [Int32: Double],
        cpuMap: [Int32: Double],
        stats: SystemStats
    )
}

class AppMonitorInteractor {
    weak var output: AppMonitorInteractorOutput?
    private var timer: Timer?
    private var lastCpuTimeMap: [Int32: UInt64] = [:]
    private var lastSampleTime: Date = Date()
    private let machNsRatio: Double

    // Cache pid→bundleID across cycles; nil means "no bundle found"
    private var pidBundleIDCache: [Int32: String?] = [:]
    private let fetchQueue = DispatchQueue(label: "com.utc.quit.fetch", qos: .userInitiated)

    init() {
        var tbInfo = mach_timebase_info_data_t()
        mach_timebase_info(&tbInfo)
        machNsRatio = Double(tbInfo.numer) / Double(tbInfo.denom)
    }

    func start() {
        fetchData()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchData()
        }
    }

    func refresh() { fetchData() }

    private func fetchData() {
        let snapshot = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
        let capturedLastCpuTimeMap = lastCpuTimeMap
        let capturedLastSampleTime = lastSampleTime
        let capturedCache = pidBundleIDCache

        fetchQueue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let elapsed = now.timeIntervalSince(capturedLastSampleTime)

            // — One pass: list all pids, get memory + bundleID for each —
            var rawPids = [Int32](repeating: 0, count: 4096)
            let pidCount = Int(proc_listallpids(&rawPids, Int32(MemoryLayout<Int32>.size * rawPids.count)))
            let livePids = Array(rawPids.prefix(pidCount).filter { $0 > 0 })

            var updatedCache = capturedCache
            // Remove dead PIDs from cache
            let livePidSet = Set(livePids)
            updatedCache = updatedCache.filter { livePidSet.contains($0.key) }

            var bundleMemory: [String: Double] = [:]  // bundleID → total MB
            var pidMemory: [Int32: Double] = [:]       // for apps without bundleID

            for pid in livePids {
                let mem = self.getMemoryUsage(pid: pid)
                pidMemory[pid] = mem

                let bundleID: String?
                if let cached = updatedCache[pid] {
                    bundleID = cached
                } else {
                    let resolved = self.bundleIDForPID(pid)
                    updatedCache[pid] = resolved
                    bundleID = resolved
                }

                if let bid = bundleID, mem > 0 {
                    bundleMemory[bid, default: 0] += mem
                }
            }

            // — Per-app lookup —
            var newMemoryMap: [Int32: Double] = [:]
            var newCpuMap: [Int32: Double] = [:]
            var newCpuTimeMap: [Int32: UInt64] = [:]

            for app in snapshot {
                let pid = app.processIdentifier

                if let bundleID = app.bundleIdentifier {
                    let mem = bundleMemory.reduce(0.0) {
                        $1.key.hasPrefix(bundleID) ? $0 + $1.value : $0
                    }
                    newMemoryMap[pid] = mem
                } else {
                    newMemoryMap[pid] = livePids.reduce(0.0) {
                        self.isDescendant(pid: $1, of: pid) ? $0 + (pidMemory[$1] ?? 0) : $0
                    }
                }

                let currentTime = self.cpuTimeForPID(pid)
                newCpuTimeMap[pid] = currentTime
                if let lastTime = capturedLastCpuTimeMap[pid], elapsed > 0, currentTime >= lastTime {
                    let deltaNs = Double(currentTime - lastTime) * self.machNsRatio
                    newCpuMap[pid] = min((deltaNs / (elapsed * 1_000_000_000.0)) * 100.0, 999.0)
                } else {
                    newCpuMap[pid] = 0
                }
            }

            let stats = SystemStats(
                memoryUsagePercentage: self.getSystemMemoryUsagePercentage(),
                memoryPressure: self.getMemoryPressure()
            )

            DispatchQueue.main.async {
                self.pidBundleIDCache = updatedCache
                self.lastCpuTimeMap = newCpuTimeMap
                self.lastSampleTime = now
                self.output?.interactorDidUpdate(
                    apps: snapshot,
                    memoryMap: newMemoryMap,
                    cpuMap: newCpuMap,
                    stats: stats
                )
            }
        }
    }

    // MARK: - Helpers

    private func getMemoryUsage(pid: Int32) -> Double {
        var info = rusage_info_v4()
        let res = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutablePointer($0))
            }
        }
        return res == 0 ? Double(info.ri_phys_footprint) / 1024.0 / 1024.0 : 0
    }

    private func bundleIDForPID(_ pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        var url = URL(fileURLWithPath: String(cString: path))
        while url.pathExtension != "app" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.pathExtension == "app" else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private func parentPID(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return result > 0 ? Int32(info.pbi_ppid) : nil
    }

    private func isDescendant(pid: Int32, of rootPID: Int32) -> Bool {
        var current = pid
        while current > 1 {
            if current == rootPID { return true }
            guard let parent = parentPID(of: current) else { return false }
            current = parent
        }
        return false
    }

    private func cpuTimeForPID(_ pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        guard ret > 0 else { return 0 }
        return info.pti_total_user + info.pti_total_system
    }

    private func getSystemMemoryUsagePercentage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        let available = (Double(stats.free_count) + Double(stats.inactive_count) + Double(stats.speculative_count)) * pageSize
        return (used / (used + available)) * 100.0
    }

    private func getMemoryPressure() -> Int {
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("vm.memory_pressure", &pressure, &size, nil, 0)
        return Int(pressure)
    }
}
