import Foundation

nonisolated enum Currency: String, CaseIterable, Identifiable, Sendable {
    case tl = "TRY"
    case usd = "USD"
    case eur = "EUR"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tl: "₺"
        case .usd: "$"
        case .eur: "€"
        }
    }

    var title: String {
        switch self {
        case .tl: "TL"
        case .usd: "USD"
        case .eur: "EUR"
        }
    }
}

nonisolated enum Direction: String, CaseIterable, Identifiable, Sendable {
    case expense = "gider"
    case income = "gelir"
    case receivable = "alacak"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "Gider"
        case .income: "Gelir"
        case .receivable: "Alacak"
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
        case .card: "Kart"
        case .cashAdvance: "Nakit Avans"
        case .loan: "Kredi"
        case .cash: "Nakit"
        case .rent: "Kira"
        case .bill: "Fatura"
        case .housing: "Konut / Tasarruf"
        case .family: "Aile / Gönderim"
        case .salary: "Maaş"
        case .receivable: "Alacak"
        case .other: "Diğer"
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
        case .pending: "Bekliyor"
        case .paid: "Ödendi"
        case .excluded: "Hariç"
        }
    }
}

nonisolated enum Banks {
    static let all = ["YapıKredi", "İşBankası", "Garanti", "Akbank", "Enpara",
                      "Ziraat", "VakıfBank", "Halkbank", "QNB", "DenizBank",
                      "TEB", "ING", "Kuveyt Türk", "Papara"]

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
