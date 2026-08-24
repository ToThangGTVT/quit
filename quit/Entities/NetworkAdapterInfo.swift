import Foundation
import SystemConfiguration
import Darwin

/// Thông tin bộ điều hợp mạng đang dùng, cho ngăn "Mạng" ở tab Hiệu suất.
struct NetworkAdapterInfo {
    let bsdName: String
    let displayName: String
    let ipv4: String
    let ipv6: String
    var mac: String = "—"
    var linkSpeedMbps: Double = 0
    var mtu: UInt32 = 0
    var router: String = "—"
    var dns: String = "—"
    var isUp: Bool = false
    var packetsIn: UInt64 = 0
    var packetsOut: UInt64 = 0
    var errorsIn: UInt64 = 0
    var errorsOut: UInt64 = 0

    var linkSpeedText: String {
        guard linkSpeedMbps > 0 else { return "—" }
        return linkSpeedMbps >= 1000
            ? String(format: "%.1f Gbps", linkSpeedMbps / 1000)
            : String(format: "%.0f Mbps", linkSpeedMbps)
    }

    static func current() -> NetworkAdapterInfo {
        var primary = ""
        var router = "—"
        var dns = "—"
        if let store = SCDynamicStoreCreate(nil, "com.utc.quit" as CFString, nil, nil),
           let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            primary = global["PrimaryInterface"] as? String ?? ""
            router = global["Router"] as? String ?? "—"
            var servers: [String] = []
            if let service = global["PrimaryService"] as? String,
               let info = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(service)/DNS" as CFString) as? [String: Any],
               let list = info["ServerAddresses"] as? [String] {
                servers = list
            }
            if servers.isEmpty,
               let info = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
               let list = info["ServerAddresses"] as? [String] {
                servers = list
            }
            if !servers.isEmpty { dns = servers.prefix(2).joined(separator: ", ") }
        }

        var display = primary.isEmpty ? L.t("Không có kết nối", "No connection") : primary
        if !primary.isEmpty,
           let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?, bsd == primary,
                   let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                    display = localized
                    break
                }
            }
        }

        let addresses = Self.addresses(for: primary)
        var info = NetworkAdapterInfo(bsdName: primary, displayName: display,
                                      ipv4: addresses.v4, ipv6: addresses.v6)
        info.router = router
        info.dns = dns
        Self.applyLinkInfo(&info)
        return info
    }

    /// MAC, tốc độ link, MTU, gói/lỗi — lấy từ bản ghi AF_LINK của interface.
    private static func applyLinkInfo(_ info: inout NetworkAdapterInfo) {
        guard !info.bsdName.isEmpty else { return }
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(first) }

        var pointer = Optional(first)
        while let addr = pointer {
            defer { pointer = addr.pointee.ifa_next }
            guard String(cString: addr.pointee.ifa_name) == info.bsdName,
                  let sockaddr = addr.pointee.ifa_addr,
                  sockaddr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            info.isUp = (addr.pointee.ifa_flags & UInt32(IFF_UP)) != 0
            if let data = addr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                info.linkSpeedMbps = Double(data.pointee.ifi_baudrate) / 1_000_000.0
                info.mtu = data.pointee.ifi_mtu
                info.packetsIn = UInt64(data.pointee.ifi_ipackets)
                info.packetsOut = UInt64(data.pointee.ifi_opackets)
                info.errorsIn = UInt64(data.pointee.ifi_ierrors)
                info.errorsOut = UInt64(data.pointee.ifi_oerrors)
            }
            let mac = sockaddr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl -> String? in
                guard Int(dl.pointee.sdl_alen) == 6 else { return nil }
                let base = UnsafeRawPointer(dl).advanced(by: 8 + Int(dl.pointee.sdl_nlen))
                return (0..<6).map { String(format: "%02x", base.load(fromByteOffset: $0, as: UInt8.self)) }
                    .joined(separator: ":")
            }
            if let mac { info.mac = mac }
        }
    }

    private static func addresses(for interface: String) -> (v4: String, v6: String) {
        guard !interface.isEmpty else { return ("—", "—") }
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return ("—", "—") }
        defer { freeifaddrs(first) }

        var v4 = "—"
        var v6 = "—"
        var pointer = Optional(first)
        while let addr = pointer {
            defer { pointer = addr.pointee.ifa_next }
            guard String(cString: addr.pointee.ifa_name) == interface,
                  let sockaddr = addr.pointee.ifa_addr else { continue }
            let family = sockaddr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sockaddr, socklen_t(sockaddr.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let value = String(cString: host)
            if family == UInt8(AF_INET) {
                v4 = value
            } else if v6 == "—", !value.hasPrefix("fe80") {
                v6 = value
            }
        }
        return (v4, v6)
    }
}
