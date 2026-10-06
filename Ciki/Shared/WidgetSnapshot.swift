import Foundation

/// Uygulamanın widget ve Apple Watch için hazırladığı özet. Tutarlar yazılırken biçimlendirilir.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Payment: Codable, Equatable, Sendable, Identifiable {
        /// Kalemin ve ayın kimliği; saatten "ödendi" işareti gelince kaydı bulmak için. Eski özetlerde yok.
        var key: String? = nil
        let title: String
        let owner: String
        let amount: String
        let dueDate: Date

        var id: String { key ?? "\(title)-\(dueDate.timeIntervalSince1970)" }
    }

    /// Saatte gezinmek için tek bir ayın özeti.
    struct MonthSummary: Codable, Equatable, Sendable, Identifiable {
        /// `Month.key`; aylar bu anahtara göre sıralanır.
        let key: Int32
        let title: String
        let net: String
        let netIsNegative: Bool
        let incoming: String
        let expense: String
        let unpaid: String
        /// O ay ödenmemiş, son ödeme günü olan giderler; tarihe göre sıralı.
        let payments: [Payment]
        let isCurrent: Bool

        var id: Int32 { key }
    }

    var monthTitle: String
    var net: String
    var netIsNegative: Bool
    var incoming: String
    var expense: String
    var unpaid: String
    /// Bu ay ödenmemiş, son ödeme günü olan giderler; tarihe göre sıralı.
    var upcoming: [Payment]
    /// Uygulama kilidi açıksa widget tutarları göstermez.
    var isPrivate: Bool
    var updatedAt: Date
    /// Geçmiş 3 ve gelecek 6 ay (saat için). Eski özetlerde yok; o zaman yalnızca bu ay gösterilir.
    var months: [MonthSummary]? = nil

    /// Saatte gösterilecek aylar; eski özetlerde yalnızca bu ay.
    var monthList: [MonthSummary] {
        if let months, !months.isEmpty { return months }
        return [MonthSummary(key: 0, title: monthTitle, net: net, netIsNegative: netIsNegative, incoming: incoming,
                             expense: expense, unpaid: unpaid, payments: upcoming, isCurrent: true)]
    }

    static let appGroup = "group.com.yakupad.Ciki"
    private static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = encoded() else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static let placeholder = WidgetSnapshot(
        monthTitle: Date.now.formatted(.dateTime.month(.wide).year()), net: "+66.258 ₺", netIsNegative: false,
        incoming: "130.000 ₺", expense: "63.742 ₺", unpaid: "39.742 ₺",
        upcoming: [
            // Kurgusal örnek: widget galerisinde ve saatte önizleme olarak görünür.
            Payment(title: "Mavi Bank Kart", owner: "Deniz", amount: "−11.240,75 ₺", dueDate: .now),
            Payment(title: "Yıldız Bank Kart", owner: "Ece", amount: "−6.210,90 ₺", dueDate: .now.addingTimeInterval(86400)),
            Payment(title: "Elektrik", owner: "Ortak", amount: "−1.065 ₺", dueDate: .now.addingTimeInterval(2 * 86400)),
        ],
        isPrivate: false, updatedAt: .now,
        months: placeholderMonths
    )

    /// Örnek özetin ayları: geçen ay (hepsi ödenmiş), bu ay ve gelecek ay.
    private static var placeholderMonths: [MonthSummary] {
        let calendar = Calendar.current
        let now = calendar.dateComponents([.year, .month], from: .now)
        let key = Int32((now.year ?? 2026) * 12 + (now.month ?? 1) - 1)
        func title(_ offset: Int) -> String {
            (calendar.date(byAdding: .month, value: offset, to: .now) ?? .now).formatted(.dateTime.month(.wide).year())
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: .now) ?? .now
        return [
            MonthSummary(key: key - 1, title: title(-1), net: "+61.904 ₺", netIsNegative: false, incoming: "122.500 ₺",
                         expense: "60.596 ₺", unpaid: "0 ₺", payments: [], isCurrent: false),
            MonthSummary(key: key, title: title(0), net: "+66.258 ₺", netIsNegative: false, incoming: "130.000 ₺",
                         expense: "63.742 ₺", unpaid: "39.742 ₺", payments: [
                            Payment(title: "Mavi Bank Kart", owner: "Deniz", amount: "−11.240,75 ₺", dueDate: .now),
                            Payment(title: "Yıldız Bank Kart", owner: "Ece", amount: "−6.210,90 ₺", dueDate: .now.addingTimeInterval(86400)),
                            Payment(title: "Elektrik", owner: "Ortak", amount: "−1.065 ₺", dueDate: .now.addingTimeInterval(2 * 86400)),
                         ], isCurrent: true),
            MonthSummary(key: key + 1, title: title(1), net: "+70.890 ₺", netIsNegative: false, incoming: "122.500 ₺",
                         expense: "51.610 ₺", unpaid: "51.610 ₺", payments: [
                            Payment(title: "Kira", owner: "Ortak", amount: "−24.000 ₺", dueDate: nextMonth),
                         ], isCurrent: false),
        ]
    }
}
