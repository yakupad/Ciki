import Foundation

/// Uygulamanın o an kullandığı dil. iOS Ayarlar → Çıkı → Dil ile değiştirilir.
nonisolated enum AppLanguage: Sendable {
    case turkish
    case english

    static var current: AppLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? .english : .turkish
    }

    /// Tutar ve tarih biçimi: "12.345,67" / "12,345.67".
    var locale: Locale {
        switch self {
        case .turkish: Locale(identifier: "tr_TR")
        case .english: Locale(identifier: "en_US")
        }
    }
}
