import SwiftUI
import AppKit
import ServiceManagement

@main
struct RunningAppsMenu: App {
    @State private var runningApps: [NSRunningApplication] = []
    @State private var memoryMap: [Int32: Double] = [:]
    
    @State private var timer: Timer? = nil
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        enableLaunchAtLogin()
    }

    var body: some Scene {
        MenuBarExtra("Quản lý App", systemImage: "memorychip") {
            VStack(alignment: .leading, spacing: 10) {
                headerView
                
                appScrollView
                
                Divider()
                
                Button("Thoát Menu Bar App") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
            .padding()
            .frame(width: 280)
            .onAppear {
                startTimer()
            }
            .onDisappear {
                stopTimer()
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
                Text("Tổng RAM: \(String(format: "%.1f", totalRAM)) MB")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .monospacedDigit() // Giữ số không bị nhảy khi thay đổi
            }
            Spacer()
            Button(action: updateAppsList) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    var appScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                if runningApps.isEmpty {
                    Text("Đang quét ứng dụng...").foregroundColor(.gray)
                }
                ForEach(runningApps, id: \.processIdentifier) { app in
                    HStack {
                        Button(action: { app.activate(options: .activateAllWindows) }) {
                            HStack {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                }
                                VStack(alignment: .leading) {
                                    Text(app.localizedName ?? "Unknown").lineLimit(1)
                                    Text("\(String(format: "%.0f", memoryMap[app.processIdentifier] ?? 0)) MB")
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

    // MARK: - Logic & Helpers
    var totalRAM: Double {
        memoryMap.values.reduce(0, +)
    }

    func startTimer() {
        updateAppsList()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateAppsList()
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func updateAppsList() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != "com.utc.quit.quit" }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        
        var newMemoryMap: [Int32: Double] = [:]
        for app in apps {
            newMemoryMap[app.processIdentifier] = getMemoryUsage(pid: app.processIdentifier)
        }
        DispatchQueue.main.async {
            self.runningApps = apps
            self.memoryMap = newMemoryMap
        }
    }

    func getMemoryUsage(pid: Int32) -> Double {
        var info = rusage_info_v4()
        let res = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutablePointer($0))
            }
        }
        return res == 0 ? Double(info.ri_resident_size) / 1024.0 / 1024.0 : 0
    }

    func forceQuitAndRefresh(app: NSRunningApplication) {
        app.forceTerminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            updateAppsList()
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
