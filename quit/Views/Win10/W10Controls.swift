import SwiftUI

// MARK: - Tab

enum TMTab: String, CaseIterable, Identifiable {
    case processes, performance, appHistory, startup, users, details, services

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processes:   return L.t("Tiến trình", "Processes")
        case .performance: return L.t("Hiệu suất", "Performance")
        case .appHistory:  return L.t("Lịch sử ứng dụng", "App history")
        case .startup:     return L.t("Khởi động", "Startup")
        case .users:       return L.t("Người dùng", "Users")
        case .details:     return L.t("Chi tiết", "Details")
        case .services:    return L.t("Dịch vụ", "Services")
        }
    }

    /// Biểu tượng trên thanh công cụ. Chọn bộ icon cùng "độ đặc" để hàng tab
    /// nhìn đều nhau, tránh trộn icon mảnh (bolt) với icon rối (gearshape.2).
    var symbol: String {
        switch self {
        case .processes:   return "list.bullet"
        case .performance: return "chart.bar"
        case .appHistory:  return "clock"
        case .startup:     return "power"
        case .users:       return "person.2"
        case .details:     return "tablecells"
        case .services:    return "gearshape"
        }
    }
}

struct W10LinkButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title).font(W10.font())
            }
            .foregroundColor(hovering ? W10.accent : W10.text)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Chân cửa sổ

struct W10Footer: View {
    let compactTitle: String
    let compactSymbol: String
    let onCompact: () -> Void
    let actionTitle: String
    let actionEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            W10LinkButton(title: compactTitle, symbol: compactSymbol, action: onCompact)
            Spacer()
            // Nút chính dùng push button mặc định của macOS.
            Button(actionTitle, action: action)
                .controlSize(.regular)
                .disabled(!actionEnabled)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(W10.chrome)
        .overlay(alignment: .top) { Rectangle().fill(W10.border).frame(height: 1) }
    }
}
