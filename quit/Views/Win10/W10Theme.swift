import SwiftUI
import AppKit

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255.0,
                  green: Double((rgb >> 8) & 0xFF) / 255.0,
                  blue: Double(rgb & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

/// Bảng màu / phông chữ mô phỏng Task Manager của Windows 10.
enum W10 {
    // Khung cửa sổ
    static let content       = Color(rgb: 0xFFFFFF)
    static let chrome        = Color(rgb: 0xF0F0F0)
    static let chromeAlt     = Color(rgb: 0xF7F7F7)
    static let border        = Color(rgb: 0xD9D9D9)
    static let borderStrong  = Color(rgb: 0xACACAC)
    static let gridLine      = Color(rgb: 0xE9E9E9)
    static let text          = Color(rgb: 0x000000)
    static let textDim       = Color(rgb: 0x646464)
    static let textFaint     = Color(rgb: 0x8A8A8A)
    static let link          = Color(rgb: 0x0066CC)
    static let selection     = Color(rgb: 0xCCE8FF)
    static let selectionEdge = Color(rgb: 0x99D1FF)
    static let hover         = Color(rgb: 0xE5F3FF)
    static let accent        = Color(rgb: 0x0078D7)

    // Đồ thị
    static let cpuLine   = Color(rgb: 0x0F6FC6)
    static let cpuFill   = Color(rgb: 0xB9DCF5)
    static let memLine   = Color(rgb: 0x8E44AD)
    static let memFill   = Color(rgb: 0xDEC5EE)
    static let diskLine  = Color(rgb: 0x2E8B45)
    static let diskFill  = Color(rgb: 0xC6E5CE)
    static let netLine   = Color(rgb: 0xB8860B)
    static let netFill   = Color(rgb: 0xF0DFB4)
    static let gpuLine   = Color(rgb: 0x1F7A7A)
    static let gpuFill   = Color(rgb: 0xC3E4E4)
    static let btLine    = Color(rgb: 0x2A5FB0)
    static let btFill    = Color(rgb: 0xD3E0F5)

    private static let hasSegoe = NSFont(name: "Segoe UI", size: 12) != nil

    static func font(_ size: CGFloat = 12, _ weight: Font.Weight = .regular) -> Font {
        hasSegoe
            ? Font.custom("Segoe UI", fixedSize: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    // MARK: - Bản đồ nhiệt (heat map) của cột CPU/Bộ nhớ/Đĩa/Mạng

    private static let heatStops: [(Double, UInt32)] = [
        (0.00, 0xFFFCE8),
        (0.14, 0xFFF3C8),
        (0.32, 0xFFE49B),
        (0.52, 0xFFC66E),
        (0.72, 0xFB9E4E),
        (0.88, 0xEE6F34),
        (1.00, 0xD6431A)
    ]

    /// Trả về màu nền ô, `nil` nếu giá trị quá nhỏ (ô để trắng như Windows).
    static func heat(_ value: Double) -> Color? {
        let v = min(max(value, 0), 1)
        guard v > 0.004 else { return nil }
        let eased = pow(v, 0.62)

        var lower = heatStops[0]
        var upper = heatStops[heatStops.count - 1]
        for index in 0..<(heatStops.count - 1) {
            if eased >= heatStops[index].0 && eased <= heatStops[index + 1].0 {
                lower = heatStops[index]
                upper = heatStops[index + 1]
                break
            }
        }
        let span = upper.0 - lower.0
        let t = span > 0 ? (eased - lower.0) / span : 0
        return Color(rgb: mix(lower.1, upper.1, t))
    }

    static func heatText(_ value: Double) -> Color {
        pow(min(max(value, 0), 1), 0.62) > 0.86 ? .white : text
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let av = Double((a >> shift) & 0xFF)
            let bv = Double((b >> shift) & 0xFF)
            return UInt32((av + (bv - av) * t).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    // MARK: - Chuẩn hoá độ nhiệt cho từng cột

    static func cpuHeat(_ percent: Double) -> Double { percent / 100.0 }

    static func memoryHeat(_ mb: Double, total: UInt64) -> Double {
        let totalMB = total > 0 ? Double(total) / 1_048_576.0 : 16384
        return mb / (totalMB * 0.5)
    }

    static func diskHeat(_ kbs: Double) -> Double { kbs / 51200.0 }

    static func netHeat(_ mbps: Double) -> Double { mbps / 5.0 }

    // MARK: - Căn nét theo lưới điểm ảnh

    /// Bề rộng đúng bằng một điểm ảnh vật lý: 0.5pt trên màn Retina (2x), 1pt trên
    /// màn 1x. Viết cứng 0.5 sẽ thành nửa điểm ảnh ở 1x và bị khử răng cưa thành
    /// một vệt xám nhoè.
    static func hairline(_ scale: CGFloat) -> CGFloat { 1 / max(scale, 1) }

    /// Đưa tâm của một nét dày `width` về đúng lưới điểm ảnh. Nét có bề rộng lẻ
    /// (1px) phải nằm giữa điểm ảnh, nét chẵn (2px) phải nằm trên đường biên —
    /// sai quy tắc này thì nét bị trải đều sang hai hàng pixel kề nhau.
    static func snap(_ value: CGFloat, width: CGFloat, scale: CGFloat) -> CGFloat {
        let s = max(scale, 1)
        let pixels = max((width * s).rounded(), 1)
        let offset: CGFloat = pixels.truncatingRemainder(dividingBy: 2) == 0 ? 0 : 0.5
        return ((value * s).rounded() + offset) / s
    }
}

/// Viền mảnh nằm **gọn bên trong** khung, dày đúng một điểm ảnh vật lý.
///
/// Thay cho `Rectangle().stroke(...)`: `stroke` vẽ nét cưỡi lên chính đường biên
/// (một nửa lọt ra ngoài), nên ở màn 1x nét 1pt bị chia đôi sang hai hàng điểm ảnh
/// với alpha 50% mỗi bên thay vì một hàng đặc.
struct W10HairlineBorder: View {
    var color: Color
    var opacity: Double = 1

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .strokeBorder(color.opacity(opacity), lineWidth: W10.hairline(displayScale))
    }
}
