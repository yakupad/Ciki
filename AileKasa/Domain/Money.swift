import Foundation

nonisolated enum Money {
    /// Uygulama dilinin sayı biçimi: Türkçe "18989", İngilizce "18989".
    static var locale: Locale { AppLanguage.current.locale }

    static let baseCurrencyKey = "baseCurrency"

    /// Toplamların gösterildiği para birimi (Ayarlar'dan seçilir, cihaza özel).
    static var baseCurrency: Currency {
        UserDefaults.standard.string(forKey: baseCurrencyKey).map(Currency.init(code:)) ?? .tl
    }

    enum SignStyle {
        /// Yalnızca eksi değerlerde işaret.
        case automatic
        /// Artı değerlerde de "+" yazılır.
        case always
        /// İşaret hiç yazılmaz.
        case never
    }

    /// "−18989 ₺", "+42320 ₺", "52319 €"
    static func string(_ value: Decimal,
                       currency: Currency = Money.baseCurrency,
                       sign: SignStyle = .automatic,
                       fractions: Bool = true,
                       locale: Locale = Money.locale) -> String {
        let magnitude = value < 0 ? -value : value
        let number = magnitude.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(fractions ? 0...2 : 0...0))
        )
        let prefix: String
        switch sign {
        case .automatic: prefix = value < 0 ? "−" : ""
        case .always: prefix = value < 0 ? "−" : (value > 0 ? "+" : "")
        case .never: prefix = ""
        }
        return "\(prefix)\(number) \(currency.symbol)"
    }

    /// Para birimi simgesi olmadan, tablo hücreleri için: "−89.965"
    static func compact(_ value: Decimal, locale: Locale = Money.locale) -> String {
        let magnitude = value < 0 ? -value : value
        let number = magnitude.formatted(.number.locale(locale).precision(.fractionLength(0)))
        return value < 0 ? "−\(number)" : number
    }
}

nonisolated extension Decimal {
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
