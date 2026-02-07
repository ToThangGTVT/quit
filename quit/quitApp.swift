import SwiftUI
import AppKit
import ServiceManagement
import Combine

class MemoryMonitor: ObservableObject {
    @Published var runningApps: [NSRunningApplication] = []
    @Published var memoryMap: [Int32: Double] = [:]
    @Published var memoryPressure: Int = 0
    @Published var memoryUsagePercentage: Double = 0
    
    private var timer: Timer?

    init() {
        startTimer()
    }

    func startTimer() {
        updateAppsList()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateAppsList()
        }
    }

    func updateAppsList() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != "com.utc.quit.quit" }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        
        var newMemoryMap: [Int32: Double] = [:]
        for app in apps {
            if let bundleID = app.bundleIdentifier {
                newMemoryMap[app.processIdentifier] =
                    memoryUsageForBundleID(bundleID)
            } else {
                newMemoryMap[app.processIdentifier] =
                    memoryUsageForAppPID(app.processIdentifier)
            }
        }
        
        let pressure = getMemoryPressure()
        let usage = getSystemMemoryUsagePercentage()
        
        DispatchQueue.main.async {
            self.runningApps = apps
            self.memoryMap = newMemoryMap
            self.memoryPressure = pressure
            self.memoryUsagePercentage = usage
        }
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

        let free = Double(stats.free_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize

        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize

        let used = active + wired + compressed
        let available = free + inactive + speculative
        let total = used + available

        return (used / total) * 100.0
    }

    private func getMemoryPressure() -> Int {
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("vm.memory_pressure", &pressure, &size, nil, 0) == 0 {
            return Int(pressure)
        }
        return 0
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
    
    private func bundleIDForPID(_ pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) <= 0 {
            return nil
        }

        let execPath = String(cString: path)

        // Lần ngược lên .app
        var url = URL(fileURLWithPath: execPath)
        while url.pathExtension != "app" && url.path != "/" {
            url.deleteLastPathComponent()
        }

        guard url.pathExtension == "app",
              let bundle = Bundle(url: url) else {
            return nil
        }

        return bundle.bundleIdentifier
    }

    private func memoryUsageForBundleID(_ bundleID: String) -> Double {
        var total: Double = 0

        var pids = [Int32](repeating: 0, count: 4096)
        let count = proc_listallpids(&pids, Int32(MemoryLayout<Int32>.size * pids.count))

        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard let pidBundleID = bundleIDForPID(pid),
                  pidBundleID.hasPrefix(bundleID) else { continue }

            total += getMemoryUsage(pid: pid)
        }

        return total
    }
    
    private func parentPID(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let result = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )

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

    private func memoryUsageForAppPID(_ appPID: Int32) -> Double {
        var total: Double = 0

        var pids = [Int32](repeating: 0, count: 4096)
        let count = proc_listallpids(&pids,
            Int32(MemoryLayout<Int32>.size * pids.count))

        for pid in pids.prefix(Int(count)) where pid > 0 {
            if isDescendant(pid: pid, of: appPID) {
                total += getMemoryUsage(pid: pid)
            }
        }

        return total
    }

}

@main
struct RunningAppsMenu: App {
    @StateObject private var monitor = MemoryMonitor()
    
    var pressureColor: Color {
        if monitor.memoryPressure == 1 { return .green }
        if monitor.memoryPressure == 2 { return .orange }
        if monitor.memoryPressure == 4 { return .red }
        
        if monitor.memoryUsagePercentage < 50 { return .green }
        if monitor.memoryUsagePercentage < 80 { return .orange }
        return .red
    }
    
    var pressureText: String {
        if monitor.memoryPressure == 1 || (monitor.memoryPressure > 0 && monitor.memoryPressure < 50) { return "Thấp" }
        if monitor.memoryPressure == 2 || (monitor.memoryPressure >= 50 && monitor.memoryPressure < 80) { return "Vừa" }
        if monitor.memoryPressure == 4 || monitor.memoryPressure >= 80 { return "Cao" }
        return "N/A"
    }
    
    @MainActor
    private func generateMenuIcon() -> NSImage? {
        let view = HStack(spacing: 2) {
            Image(systemName: "memorychip").frame(width: 20, height: 20)
            Text("\(Int(monitor.memoryUsagePercentage))%")
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
            .foregroundStyle(.windowBackground)
        .padding(.horizontal, 4)
        
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        renderer.colorMode = .extendedLinear
        return renderer.nsImage
    }
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        enableLaunchAtLogin()
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                headerView
                appScrollView
                Button("Thoát Menu Bar App") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
            .padding()
            .frame(width: 280)
        } label: {
            if let icon = generateMenuIcon() {
                Image(nsImage: icon)
                    .renderingMode(.original)
            } else {
                Image(systemName: "memorychip")
            }
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Components
    var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Ứng dụng đang mở")
                    .font(.headline)
                HStack(spacing: 4) {
                    let totalRAM = monitor.memoryMap.values.reduce(0, +)
                    Text("RAM: \(String(format: "%.1f", totalRAM)) MB")
                        .foregroundColor(.blue)
                    Text("|")
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Áp lực: \(pressureText) (\(monitor.memoryPressure))")
                        .foregroundColor(pressureColor)
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
            }
            Spacer()
            Button(action: { monitor.updateAppsList() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    var appScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                if monitor.runningApps.isEmpty {
                    Text("Đang quét ứng dụng...").foregroundColor(.gray)
                }
                ForEach(monitor.runningApps, id: \.processIdentifier) { app in
                    HStack {
                        Button(action: { app.activate(options: .activateAllWindows) }) {
                            HStack {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                }
                                VStack(alignment: .leading) {
                                    Text(app.localizedName ?? "Unknown").lineLimit(1)
                                    Text("\(String(format: "%.0f", monitor.memoryMap[app.processIdentifier] ?? 0)) MB")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: { forceQuitAndRefresh(app: app) }) {
                            Image(systemName: "xmark.circle.fill").resizable().frame(width: 16, height: 16)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: 400)
    }

    func forceQuitAndRefresh(app: NSRunningApplication) {
        app.forceTerminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            monitor.updateAppsList()
        }
    }
    
    func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print(error)
        }
    }
}
