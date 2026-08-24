import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }
    var title: String { self == .vietnamese ? "Tiếng Việt" : "English" }
}

/// Ngôn ngữ hiện tại. Là `@Observable` nên mọi view gọi `L.t(...)` trong body
/// sẽ tự vẽ lại khi đổi ngôn ngữ — không cần khởi động lại app.
@Observable
final class L10n {
    static let shared = L10n()
    private static let key = "AppLanguage"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            // Có tiếng Việt trong danh sách ngôn ngữ hệ thống thì mặc định tiếng Việt.
            let hasVietnamese = Locale.preferredLanguages.contains { $0.hasPrefix("vi") }
            language = hasVietnamese ? .vietnamese : .english
        }
    }
}

/// `L.t("tiếng Việt", "English")`
enum L {
    static func t(_ vi: String, _ en: String) -> String {
        L10n.shared.language == .vietnamese ? vi : en
    }
}
