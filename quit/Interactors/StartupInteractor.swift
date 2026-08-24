import Foundation

/// Đọc dữ liệu cho hai tab "Khởi động" và "Dịch vụ".
/// Chỉ đọc khi mở tab, không lấy mẫu định kỳ.
class StartupInteractor {

    func loadStartupItems() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sources: [(path: String, scope: String)] = [
            ("\(home)/Library/LaunchAgents", L.t("Người dùng", "Users")),
            ("/Library/LaunchAgents", L.t("Hệ thống", "System")),
            ("/Library/LaunchDaemons", L.t("Hệ thống", "System"))
        ]

        var items: [StartupItem] = []
        for source in sources {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
            for file in files where file.hasSuffix(".plist") {
                let full = "\(source.path)/\(file)"
                guard let data = FileManager.default.contents(atPath: full),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil) as? [String: Any]
                else { continue }

                let label = (plist["Label"] as? String) ?? (file as NSString).deletingPathExtension
                let disabled = (plist["Disabled"] as? Bool) ?? false
                var program = plist["Program"] as? String
                if program == nil, let args = plist["ProgramArguments"] as? [String] {
                    program = args.first
                }
                items.append(StartupItem(
                    id: "\(source.scope)/\(label)",
                    name: label,
                    publisher: Self.publisher(for: label),
                    enabled: !disabled,
                    scope: source.scope,
                    path: program ?? full
                ))
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadServices() -> [ServiceItem] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var items: [ServiceItem] = []
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let label = String(parts[2]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            items.append(ServiceItem(
                id: label,
                pid: Int32(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0,
                status: Int32(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
                scope: label.hasPrefix("com.apple.") ? L.t("Hệ thống", "System") : L.t("Người dùng", "Users")
            ))
        }
        return items.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private static func publisher(for label: String) -> String {
        if label.hasPrefix("com.apple.") { return "Apple Inc." }
        let parts = label.components(separatedBy: ".")
        if parts.count >= 2 { return parts[1].capitalized }
        return "—"
    }
}
