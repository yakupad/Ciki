import Foundation

/// Uygulamanın widget için App Group'a yazdığı özet. Tutarlar yazılırken biçimlendirilir.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Payment: Codable, Equatable, Sendable {
        let title: String
        let owner: String
        let amount: String
        let dueDate: Date
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

    static let appGroup = "group.com.yakupad.AileKasa"
    private static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    static let placeholder = WidgetSnapshot(
        monthTitle: "Ekim 2026", net: "−45653 ₺", netIsNegative: true,
        incoming: "34543 ₺", expense: "35654 ₺", unpaid: "36765 ₺",
        upcoming: [
            Payment(title: "YapıKredi Kart", owner: "Deniz", amount: "−18989 ₺", dueDate: .now),
            Payment(title: "İşBankası Kart", owner: "Deniz", amount: "−23433 ₺", dueDate: .now),
            Payment(title: "YapıKredi Kart", owner: "Ece", amount: "−28988 ₺", dueDate: .now.addingTimeInterval(2 * 86400)),
        ],
        isPrivate: false, updatedAt: .now
    )
}
