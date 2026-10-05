import Foundation

/// ISO 4217 kodlu para birimi. TL dışındakilerin kuru TCMB'den gelir.
nonisolated struct Currency: Hashable, Identifiable, Sendable {
    let code: String

    init(code: String) {
        self.code = code.uppercased()
    }

    static let tl = Currency(code: "TRY")
    static let usd = Currency(code: "USD")
    static let eur = Currency(code: "EUR")
    static let gbp = Currency(code: "GBP")

    /// TCMB'nin günlük yayımladığı para birimleri; sık kullanılanlar önde.
    static let all: [Currency] = ["TRY", "USD", "EUR", "GBP", "CHF", "JPY", "CAD", "AUD",
                                  "SAR", "AED", "QAR", "KWD", "AZN", "RUB", "CNY", "SEK",
                                  "NOK", "DKK", "RON", "KRW", "PKR", "KZT"].map(Currency.init(code:))
    /// Seçicide üstte gösterilen birimler.
    static let common: [Currency] = [.tl, .usd, .eur, .gbp, Currency(code: "CHF")]

    var id: String { code }

    var symbol: String {
        switch code {
        case "TRY": "₺"
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        case "JPY": "¥"
        case "CNY": "CN¥"
        case "CAD": "C$"
        case "AUD": "A$"
        case "RUB": "₽"
        case "AZN": "₼"
        case "KRW": "₩"
        case "KZT": "₸"
        default: code
        }
    }

    /// Kısa ad: "TL", "USD", "EUR"…
    var title: String { self == .tl ? "TL" : code }

    /// Uygulama dilinde tam ad: "ABD Doları" / "US Dollar".
    var name: String {
        AppLanguage.current.locale.localizedString(forCurrencyCode: code)?.capitalized(with: AppLanguage.current.locale) ?? code
    }
}

nonisolated enum Direction: String, CaseIterable, Identifiable, Sendable {
    case expense = "gider"
    case income = "gelir"
    case receivable = "alacak"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: String(localized: "Gider")
        case .income: String(localized: "Gelir")
        case .receivable: String(localized: "Alacak")
        }
    }

    /// Giderler eksi, gelir ve alacaklar artı yazılır.
    var sign: Decimal { self == .expense ? -1 : 1 }
}

nonisolated enum ItemKind: String, CaseIterable, Identifiable, Sendable {
    case card = "kart"
    case cashAdvance = "nakitAvans"
    case loan = "kredi"
    case cash = "nakit"
    case rent = "kira"
    case bill = "fatura"
    case housing = "konut"
    case family = "aile"
    case salary = "maas"
    case receivable = "alacak"
    case other = "diger"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: String(localized: "Kart")
        case .cashAdvance: String(localized: "Nakit Avans")
        case .loan: String(localized: "Kredi")
        case .cash: String(localized: "Nakit")
        case .rent: String(localized: "Kira")
        case .bill: String(localized: "Fatura")
        case .housing: String(localized: "Konut / Tasarruf")
        case .family: String(localized: "Aile / Gönderim")
        case .salary: String(localized: "Maaş")
        case .receivable: String(localized: "Alacak")
        case .other: String(localized: "Diğer")
        }
    }

    var symbol: String {
        switch self {
        case .card: "creditcard.fill"
        case .cashAdvance: "banknote.fill"
        case .loan: "building.columns.fill"
        case .cash: "turkishlirasign.circle.fill"
        case .rent: "house.fill"
        case .bill: "bolt.fill"
        case .housing: "building.2.fill"
        case .family: "heart.fill"
        case .salary: "briefcase.fill"
        case .receivable: "arrow.down.circle.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var defaultDirection: Direction {
        switch self {
        case .salary: .income
        case .receivable: .receivable
        default: .expense
        }
    }

    /// Banka ürünleri banka adıyla birlikte gösterilir.
    var isBankProduct: Bool {
        switch self {
        case .card, .cashAdvance, .loan, .cash: true
        default: false
        }
    }
}

nonisolated enum EntryStatus: String, CaseIterable, Identifiable, Sendable {
    case pending = "bekliyor"
    case paid = "odendi"
    case excluded = "haric"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: String(localized: "Bekliyor")
        case .paid: String(localized: "Ödendi")
        case .excluded: String(localized: "Hariç")
        }
    }
}

nonisolated enum Banks {
    static let all = ["YapıKredi", "İşBankası", "Garanti", "Akbank", "Enpara",
                      "Ziraat", "VakıfBank", "Halkbank", "QNB", "DenizBank",
                      "TEB", "ING", "Kuveyt Türk", "Papara"]

    /// Karşılaştırma anahtarı: büyük/küçük harf ve boşluklar yok sayılır ("Yapı Kredi" = "yapıkredi").
    static func key(_ name: String) -> String {
        name.lowercased(with: Locale(identifier: "tr_TR")).filter { !$0.isWhitespace }
    }

    /// Bilinen bir bankaysa listedeki yazımı döner, değilse girilen adı.
    static func canonical(_ name: String) -> String {
        let target = key(name)
        return all.first { key($0) == target } ?? name
    }

    /// TR IBAN'ın 5–9. hanelerindeki banka kodundan banka adı.
    static func name(forIBAN iban: String) -> String? {
        let compact = IBAN.normalized(iban)
        guard compact.hasPrefix("TR"), compact.count >= 9 else { return nil }
        let code = String(compact.dropFirst(4).prefix(5))
        return codes[code]
    }

    private static let codes: [String: String] = [
        "00010": "Ziraat", "00012": "Halkbank", "00015": "VakıfBank", "00032": "TEB",
        "00046": "Akbank", "00062": "Garanti", "00064": "İşBankası", "00067": "YapıKredi",
        "00099": "ING", "00111": "QNB", "00134": "DenizBank", "00205": "Kuveyt Türk",
    ]

    static func initials(for bank: String) -> String {
        switch bank {
        case "YapıKredi": return "YK"
        case "İşBankası": return "İŞ"
        case "VakıfBank": return "VB"
        case "DenizBank": return "DB"
        case "Kuveyt Türk": return "KT"
        default:
            return String(bank.prefix(2)).uppercased(with: Locale(identifier: "tr_TR"))
        }
    }

    /// Koyu modda okunabilmesi için bankanın renginin %40 beyazla karıştırılmış hali.
    static func darkColorHex(for bank: String) -> UInt32 {
        let hex = colorHex(for: bank)
        func lift(_ channel: UInt32) -> UInt32 { channel + (255 - channel) * 2 / 5 }
        return lift((hex >> 16) & 0xFF) << 16 | lift((hex >> 8) & 0xFF) << 8 | lift(hex & 0xFF)
    }

    static func colorHex(for bank: String) -> UInt32 {
        switch bank {
        case "YapıKredi": 0x1B4F9C
        case "İşBankası": 0x2A5AA8
        case "Garanti": 0x2E7D5B
        case "Akbank": 0xC8372D
        case "Enpara": 0x6C2BD9
        case "Ziraat": 0xB3261E
        case "VakıfBank": 0xB8860B
        case "Halkbank": 0x1F6FB2
        case "QNB": 0x5B2A86
        case "DenizBank": 0x1565C0
        case "TEB": 0x00845A
        case "ING": 0xE0681B
        case "Kuveyt Türk": 0x0B7A4B
        case "Papara": 0x4B3FA8
        default: 0x4A5A55
        }
    }
}
