import CoreData

// CloudKit uyumluluğu için tüm öznitelikler isteğe bağlıdır ve benzersizlik kısıtı yoktur.
// Sınıflar Core Data'nın kendi kuyruklarından da erişilebildiği için ana aktöre bağlı değildir.

@objc(Household)
nonisolated final class Household: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var people: NSSet?
    @NSManaged var items: NSSet?
    @NSManaged var accounts: NSSet?
}

@objc(Person)
nonisolated final class Person: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var colorHex: String?
    @NSManaged var relationRaw: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var household: Household?
    @NSManaged var items: NSSet?
    @NSManaged var accounts: NSSet?
}

@objc(LedgerItem)
nonisolated final class LedgerItem: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var bank: String?
    @NSManaged var kindRaw: String?
    @NSManaged var directionRaw: String?
    @NSManaged var currencyCode: String?
    @NSManaged var dueDay: Int16
    @NSManaged var sortOrder: Int32
    @NSManaged var isArchived: Bool
    @NSManaged var isRecurring: Bool
    @NSManaged var recurringAmount: NSDecimalNumber?
    @NSManaged var recurringStart: Int32
    @NSManaged var recurringEnd: Int32
    /// Düzenli tutarın sonraki değişiklikleri (JSON). Bkz. `amountChanges`.
    @NSManaged var recurringChanges: String?
    @NSManaged var note: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var updatedBy: String?
    @NSManaged var household: Household?
    @NSManaged var owner: Person?
    @NSManaged var payee: Account?
    @NSManaged var entries: NSSet?
}

/// Banka hesabı: ailenin kendi hesabı ya da ödeme yapılan kişi/kurumun hesabı.
@objc(Account)
nonisolated final class Account: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String?
    @NSManaged var holderName: String?
    @NSManaged var bank: String?
    @NSManaged var iban: String?
    @NSManaged var currencyCode: String?
    @NSManaged var isOwn: Bool
    /// Kendi hesaplarda güncel bakiye (nakit varlık). Girilmemişse nil.
    @NSManaged var balance: NSDecimalNumber?
    @NSManaged var balanceUpdatedAt: Date?
    @NSManaged var note: String?
    @NSManaged var sortOrder: Int32
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var owner: Person?
    @NSManaged var items: NSSet?
}

@objc(LedgerEntry)
nonisolated final class LedgerEntry: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var monthKey: Int32
    @NSManaged var amount: NSDecimalNumber?
    @NSManaged var statusRaw: String?
    @NSManaged var rate: NSDecimalNumber?
    @NSManaged var paidAt: Date?
    /// Kısmi ödemeler (JSON). Bkz. `paymentList`.
    @NSManaged var payments: String?
    /// Önceki aydan bu kayda devredilen kalan.
    @NSManaged var carriedIn: NSDecimalNumber?
    /// Bu kaydın ödenmeyen kalanından sonraki bir aya devredilen kısım.
    @NSManaged var carriedOut: NSDecimalNumber?
    /// `carriedOut`'un devredildiği ayın anahtarı; devir yoksa 0.
    @NSManaged var carriedToKey: Int32
    @NSManaged var note: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    /// Değişikliği yapan telefonun kişisi (Ayarlar → Bu telefonu kullanan).
    @NSManaged var updatedBy: String?
    @NSManaged var item: LedgerItem?
}

// MARK: - Kolaylıklar

nonisolated extension Household {
    var peopleArray: [Person] {
        ((people as? Set<Person>) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

nonisolated extension Person {
    /// Kişi renkleri; yeni kişiye kullanılmayan ilk renk verilir.
    static let palette = ["3D5FD9", "C23F7B", "D9822B", "2E9E6B", "7A4FD1", "1F8FB0", "B5452E", "6B7A2E"]

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "İsimsiz") : trimmed
    }

    var relation: PersonRelation? {
        get { relationRaw.flatMap(PersonRelation.init(rawValue:)) }
        set { relationRaw = newValue?.rawValue }
    }

    /// Seçicilerde: "Ece · Eş"; yakınlık seçilmemişse yalnızca ad.
    var displayNameWithRelation: String {
        relation.map { "\(displayName) · \($0.title)" } ?? displayName
    }
}

nonisolated extension LedgerItem {
    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw ?? "") ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var direction: Direction {
        get { Direction(rawValue: directionRaw ?? "") ?? .expense }
        set { directionRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { currencyCode.map(Currency.init(code:)) ?? .tl }
        set { currencyCode = newValue.code }
    }

    /// Sahibin adı; sahibi yoksa "Ortak".
    var ownerName: String {
        owner?.displayName ?? String(localized: "Ortak")
    }

    var bankName: String? {
        let trimmed = (bank ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Banks.canonical(trimmed)
    }

    /// Kalemin kendi adı; boşsa türün adı ("Kart").
    var title: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    /// Banka adıyla birlikte: "YapıKredi Kart".
    var fullTitle: String {
        if let bankName { "\(bankName) \(title)" } else { title }
    }

    var recurringAmountValue: Decimal? {
        get { recurringAmount as Decimal? }
        set { recurringAmount = newValue.map { NSDecimalNumber(decimal: $0) } }
    }

    var entriesArray: [LedgerEntry] {
        ((entries as? Set<LedgerEntry>) ?? []).sorted { $0.monthKey < $1.monthKey }
    }

    func entry(for month: Month) -> LedgerEntry? {
        ((entries as? Set<LedgerEntry>) ?? []).first { $0.monthKey == month.key }
    }

    /// "Şu aydan itibaren şu tutar" değişiklikleri, aya göre sıralı. Ör. Ocak'tan itibaren 125.000.
    var amountChanges: [AmountChange] {
        get {
            guard let data = recurringChanges?.data(using: .utf8),
                  let changes = try? JSONDecoder().decode([AmountChange].self, from: data) else { return [] }
            return changes.sorted { $0.from < $1.from }
        }
        set {
            let sorted = newValue.sorted { $0.from < $1.from }
            recurringChanges = sorted.isEmpty ? nil : (try? JSONEncoder().encode(sorted)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    /// O ay geçerli olan düzenli tutar: ayından önceki son değişiklik, yoksa ilk tutar.
    func recurringAmount(in month: Month) -> Decimal? {
        guard let base = recurringAmountValue else { return nil }
        return amountChanges.last { $0.from <= month.key }?.amount ?? base
    }

    func isRecurringActive(in month: Month) -> Bool {
        guard isRecurring, !isArchived, recurringAmount != nil else { return false }
        if recurringStart != 0, month.key < recurringStart { return false }
        if recurringEnd != 0, month.key > recurringEnd { return false }
        return true
    }
}

nonisolated extension Account {
    var currency: Currency {
        get { currencyCode.map(Currency.init(code:)) ?? .tl }
        set { currencyCode = newValue.code }
    }

    var bankName: String? {
        let trimmed = (bank ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Banks.canonical(trimmed)
    }

    /// Listede görünen ad: hesap adı, yoksa alıcı adı, yoksa banka.
    var displayTitle: String {
        for candidate in [title, holderName, bankName] {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return String(localized: "Adsız hesap")
    }

    var formattedIBAN: String { IBAN.formatted(iban ?? "") }

    var balanceValue: Decimal? {
        get { balance as Decimal? }
        set { balance = newValue.map { NSDecimalNumber(decimal: $0) } }
    }

    var itemsArray: [LedgerItem] {
        ((items as? Set<LedgerItem>) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Paylaşım ve kopyalama için: ad, banka, IBAN.
    var shareText: String {
        [holderName, bankName, iban.map(IBAN.formatted)]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

nonisolated extension LedgerEntry {
    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw ?? "") ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var amountValue: Decimal {
        get { (amount as Decimal?) ?? 0 }
        set { amount = NSDecimalNumber(decimal: newValue) }
    }

    var rateValue: Decimal? {
        get { rate as Decimal? }
        set { rate = newValue.map { NSDecimalNumber(decimal: $0) } }
    }

    var month: Month { Month(key: monthKey) }

    var paymentList: [EntryPayment] {
        get {
            guard let data = payments?.data(using: .utf8),
                  let list = try? JSONDecoder().decode([EntryPayment].self, from: data) else { return [] }
            return list.sorted { $0.date < $1.date }
        }
        set {
            let sorted = newValue.sorted { $0.date < $1.date }
            payments = sorted.isEmpty ? nil : (try? JSONEncoder().encode(sorted)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var carriedInValue: Decimal {
        get { (carriedIn as Decimal?) ?? 0 }
        set { carriedIn = newValue == 0 ? nil : NSDecimalNumber(decimal: newValue) }
    }

    var carriedOutValue: Decimal {
        get { (carriedOut as Decimal?) ?? 0 }
        set { carriedOut = newValue == 0 ? nil : NSDecimalNumber(decimal: newValue) }
    }

    /// Bu ayın payına düşen tutar: girilen tutar + devralınan − devredilen.
    var dueValue: Decimal { amountValue + carriedInValue - carriedOutValue }

    /// Ödenen kısım. Ödendi durumunda tamamı, değilse kısmi ödemelerin toplamı.
    var paidValue: Decimal {
        switch status {
        case .paid: dueValue
        case .excluded: 0
        case .pending: min(paymentList.reduce(0) { $0 + $1.amount }, max(dueValue, 0))
        }
    }

    /// Ödenmeyi bekleyen kalan.
    var remainingValue: Decimal {
        status == .pending ? max(dueValue - paidValue, 0) : 0
    }

    /// Kısmen ödenmiş, kalanı bekleyen kayıt.
    var isPartiallyPaid: Bool { status == .pending && paidValue > 0 && remainingValue > 0 }
}

/// Bir kaydın kısmi ödemesi. Ör. 50.000'lik kartın 30.000'i 5 Ekim'de.
nonisolated struct EntryPayment: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var amount: Decimal
}

/// Düzenli bir kalemin tutarının belli bir aydan itibaren değişmesi.
nonisolated struct AmountChange: Codable, Hashable, Identifiable, Sendable {
    /// Değişikliğin başladığı ayın anahtarı (`Month.key`).
    var from: Int32
    var amount: Decimal

    var id: Int32 { from }
    var month: Month { Month(key: from) }
}
