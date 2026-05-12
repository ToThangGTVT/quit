import AppKit

protocol AppMonitorInteractorOutput: AnyObject {
    func interactorDidUpdate(entities: [AppEntity], stats: SystemStats)
}

class AppMonitorInteractor {
    weak var output: AppMonitorInteractorOutput?
    private var timer: Timer?
    private var lastCpuTimeMap: [Int32: UInt64] = [:]
    private var lastSampleTime: Date = Date()
    private let machNsRatio: Double

    private var lastNetTcpMap: [Int32: (rx: UInt64, tx: UInt64)] = [:]
    private var lastSysNetRx: UInt64 = 0
    private var lastSysNetTx: UInt64 = 0
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
        let nsApps = NSWorkspace.shared.runningApplications
        let nsAppsMap = Dictionary(
            nsApps.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let capturedLastCpuTimeMap = lastCpuTimeMap
        let capturedLastNetTcpMap = lastNetTcpMap
        let capturedLastSampleTime = lastSampleTime
        let capturedSysNetRx = lastSysNetRx
        let capturedSysNetTx = lastSysNetTx

        fetchQueue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let elapsed = now.timeIntervalSince(capturedLastSampleTime)
            let nettopMap = self.fetchNettopData()

            var rawPids = [Int32](repeating: 0, count: 4096)
            let pidCount = Int(proc_listallpids(&rawPids, Int32(MemoryLayout<Int32>.size * rawPids.count)))
            let livePids = rawPids.prefix(pidCount).filter { $0 > 0 }

            let (sysRx, sysTx) = self.getSystemNetworkBytes()
            let sysNetRxKBs = elapsed > 0 && sysRx >= capturedSysNetRx
                ? Double(sysRx - capturedSysNetRx) / elapsed / 1024 : 0
            let sysNetTxKBs = elapsed > 0 && sysTx >= capturedSysNetTx
                ? Double(sysTx - capturedSysNetTx) / elapsed / 1024 : 0

            var newCpuTimeMap: [Int32: UInt64] = [:]
            var newNetTcpMap: [Int32: (rx: UInt64, tx: UInt64)] = [:]
            var entities: [AppEntity] = []

            for pid in livePids {
                let mem = self.getMemoryUsage(pid: pid)

                let nsApp = nsAppsMap[pid]
                let name: String
                if let localizedName = nsApp?.localizedName, !localizedName.isEmpty {
                    name = localizedName
                } else {
                    name = self.processName(pid: pid)
                }

                if name.isEmpty && mem == 0 { continue }

                let currentCpuTime = self.cpuTimeForPID(pid)
                newCpuTimeMap[pid] = currentCpuTime
                let cpu: Double
                if let lastTime = capturedLastCpuTimeMap[pid], elapsed > 0, currentCpuTime >= lastTime {
                    let deltaNs = Double(currentCpuTime - lastTime) * self.machNsRatio
                    let coreCount = Double(ProcessInfo.processInfo.processorCount)
                    cpu = min((deltaNs / (elapsed * 1_000_000_000.0 * coreCount)) * 100.0, 100.0)
                } else {
                    cpu = 0
                }

                let curRx = nettopMap[pid]?.rx ?? 0
                let curTx = nettopMap[pid]?.tx ?? 0
                newNetTcpMap[pid] = (curRx, curTx)
                let netRx: Double
                let netTx: Double
                if let last = capturedLastNetTcpMap[pid], elapsed > 0, curRx >= last.rx, curTx >= last.tx {
                    netRx = Double(curRx - last.rx) / elapsed / 1024
                    netTx = Double(curTx - last.tx) / elapsed / 1024
                } else {
                    netRx = 0
                    netTx = 0
                }

                entities.append(AppEntity(
                    id: pid,
                    name: name,
                    memory: mem,
                    cpu: cpu,
                    netRxKBs: netRx,
                    netTxKBs: netTx,
                    runningApp: nsApp
                ))
            }

            let stats = SystemStats(
                memoryUsagePercentage: self.getSystemMemoryUsagePercentage(),
                memoryPressure: self.getMemoryPressure(),
                netRxKBs: sysNetRxKBs,
                netTxKBs: sysNetTxKBs
            )

            DispatchQueue.main.async {
                self.lastCpuTimeMap = newCpuTimeMap
                self.lastNetTcpMap = newNetTcpMap
                self.lastSysNetRx = sysRx
                self.lastSysNetTx = sysTx
                self.lastSampleTime = now
                self.output?.interactorDidUpdate(entities: entities, stats: stats)
            }
        }
    }

    // MARK: - Helpers

    private func processName(pid: Int32) -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            return URL(fileURLWithPath: String(cString: path)).lastPathComponent
        }
        var name = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &name, UInt32(name.count)) > 0 {
            return String(cString: name)
        }
        return "pid:\(pid)"
    }

    private func getMemoryUsage(pid: Int32) -> Double {
        var info = rusage_info_v4()
        let res = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutablePointer($0))
            }
        }
        return res == 0 ? Double(info.ri_phys_footprint) / 1024.0 / 1024.0 : 0
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

    private func getSystemNetworkBytes() -> (rx: UInt64, tx: UInt64) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        defer { freeifaddrs(first) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr = Optional(first)
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            if !name.hasPrefix("lo"),
               addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                if let data = addr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    rx += UInt64(data.pointee.ifi_ibytes)
                    tx += UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = addr.pointee.ifa_next
        }
        return (rx, tx)
    }

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
            if let ex = result[pid] {
                result[pid] = (ex.rx + rx, ex.tx + tx)
            } else {
                result[pid] = (rx, tx)
            }
        }
        return result
    }
}
