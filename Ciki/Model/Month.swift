import Foundation

/// Takvim ayı. `key = yıl * 12 + (ay - 1)` olarak saklanır; aylar arası aritmetik tamsayı toplamadır.
nonisolated struct Month: Hashable, Comparable, Identifiable, Sendable {
    let key: Int32

    init(key: Int32) {
        self.key = key
    }

    init(year: Int, month: Int) {
        self.key = Int32(year * 12 + month - 1)
    }

    static var current: Month {
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        return Month(year: parts.year ?? 2026, month: parts.month ?? 1)
    }

    var id: Int32 { key }
    var year: Int { Int(key) / 12 }
    var month: Int { Int(key) % 12 + 1 }

    func adding(_ months: Int) -> Month {
        Month(key: key + Int32(months))
    }

    func distance(to other: Month) -> Int {
        Int(other.key - key)
    }

    static func < (lhs: Month, rhs: Month) -> Bool {
        lhs.key < rhs.key
    }

    static func names(in language: AppLanguage = .current) -> [String] {
        switch language {
        case .turkish: ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                        "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
        case .english: ["January", "February", "March", "April", "May", "June",
                        "July", "August", "September", "October", "November", "December"]
        }
    }

    static func shortNames(in language: AppLanguage = .current) -> [String] {
        switch language {
        case .turkish: ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
        case .english: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        }
    }

    var name: String { Self.names()[month - 1] }
    var shortName: String { Self.shortNames()[month - 1] }

    /// "Ekim 2026" / "October 2026"
    func title(in language: AppLanguage = .current) -> String {
        "\(Self.names(in: language)[month - 1]) \(year)"
    }

    var title: String { title() }
    /// "Eki '26"
    var shortTitle: String { "\(shortName) '\(String(year).suffix(2))" }

    var daysInMonth: Int {
        let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        return Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// Ödeme günü ayın gün sayısını aşıyorsa son güne çekilir (ör. 31 → Şubat 28).
    func clampedDay(_ day: Int) -> Int {
        min(max(day, 1), daysInMonth)
    }
}
