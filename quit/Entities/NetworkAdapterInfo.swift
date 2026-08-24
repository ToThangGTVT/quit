import Foundation
import SystemConfiguration
import Darwin

/// Thông tin bộ điều hợp mạng đang dùng, cho ngăn "Mạng" ở tab Hiệu suất.
struct NetworkAdapterInfo {
    let bsdName: String
    let displayName: String
    let ipv4: String
    let ipv6: String

    static func current() -> NetworkAdapterInfo {
        var primary = ""
        if let store = SCDynamicStoreCreate(nil, "com.utc.quit" as CFString, nil, nil),
           let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let name = global["PrimaryInterface"] as? String {
            primary = name
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
        return NetworkAdapterInfo(bsdName: primary, displayName: display,
                                  ipv4: addresses.v4, ipv6: addresses.v6)
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
