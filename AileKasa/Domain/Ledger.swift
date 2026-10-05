import CoreData

/// TL karşılığı bilinen döviz kurları (1 birim = x ₺).
nonisolated struct RateTable: Equatable, Sendable {
    var usd: Decimal?
    var eur: Decimal?

    func rate(for currency: Currency) -> Decimal? {
        switch currency {
        case .tl: 1
        case .usd: usd
        case .eur: eur
        }
    }
}

/// Bir kalemin belirli bir aydaki satırı. Kayıt yoksa ve kalem düzenliyse tahmini satır üretilir.
struct LedgerLine: Identifiable {
    let item: LedgerItem
    let entry: LedgerEntry?
    let month: Month
    /// Kalemin kendi para biriminde, işaretsiz tutar.
    let amount: Decimal
    let status: EntryStatus
    /// İşaretli TL karşılığı. Kur bilinmiyorsa nil.
    let signedTRY: Decimal?

    var id: NSManagedObjectID { item.objectID }
    var isProjected: Bool { entry == nil }
    var currency: Currency { item.currency }
    var direction: Direction { item.direction }
    var counts: Bool { status != .excluded }
}

struct MonthSummary {
    var income: Decimal = 0
    var receivable: Decimal = 0
    /// Pozitif olarak tutulur.
    var expense: Decimal = 0
    var unpaidExpense: Decimal = 0
    /// Kişi bazında net. `nil` anahtarı ortak kalemlerdir.
    var byOwner: [NSManagedObjectID?: Decimal] = [:]
    /// Kuru bilinmediği için toplama girmeyen satır sayısı.
    var missingRateCount = 0

    var net: Decimal { income + receivable - expense }

    func net(for owner: Person?) -> Decimal {
        byOwner[owner?.objectID] ?? 0
    }
}

enum Ledger {
    static func lines(for month: Month, items: some Sequence<LedgerItem>, rates: RateTable) -> [LedgerLine] {
        items.compactMap { line(for: $0, month: month, rates: rates) }
    }

    static func line(for item: LedgerItem, month: Month, rates: RateTable) -> LedgerLine? {
        let amount: Decimal
        let status: EntryStatus
        var rate = rates.rate(for: item.currency)

        if let entry = item.entry(for: month) {
            amount = entry.amountValue
            status = entry.status
            // Ödenmiş döviz kaydı ödeme günündeki kurla sabitlenir.
            if status == .paid, let stored = entry.rateValue {
                rate = stored
            }
            return LedgerLine(item: item, entry: entry, month: month, amount: amount, status: status,
                              signedTRY: rate.map { amount * $0 * item.direction.sign })
        }

        guard item.isRecurringActive(in: month), let recurring = item.recurringAmountValue else {
            return nil
        }
        amount = recurring
        status = .pending
        return LedgerLine(item: item, entry: nil, month: month, amount: amount, status: status,
                          signedTRY: rate.map { amount * $0 * item.direction.sign })
    }

    static func summary(of lines: [LedgerLine]) -> MonthSummary {
        var summary = MonthSummary()
        for line in lines where line.counts {
            guard let value = line.signedTRY else {
                summary.missingRateCount += 1
                continue
            }
            switch line.direction {
            case .income: summary.income += value
            case .receivable: summary.receivable += value
            case .expense:
                summary.expense -= value
                if line.status == .pending { summary.unpaidExpense -= value }
            }
            summary.byOwner[line.item.owner?.objectID, default: 0] += value
        }
        return summary
    }

    /// Toplamı kuruş hassasiyetinde eşit taksitlere böler; artan kuruşlar son taksite eklenir.
    static func split(_ total: Decimal, into count: Int) -> [Decimal] {
        guard count > 1 else { return [total] }
        let part = (total / Decimal(count)).rounded(scale: 2, mode: .down)
        let last = total - part * Decimal(count - 1)
        return Array(repeating: part, count: count - 1) + [last]
    }
}
