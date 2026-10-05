import CoreData

extension NSManagedObjectContext {
    /// Kalemin o aydaki kaydını oluşturur ya da günceller.
    @discardableResult
    func upsertEntry(item: LedgerItem, month: Month, amount: Decimal,
                     status: EntryStatus, note: String? = nil, rates: RateTable) -> LedgerEntry {
        let entry = item.entry(for: month) ?? {
            let created = LedgerEntry(context: self)
            created.uuid = UUID()
            created.createdAt = .now
            created.monthKey = month.key
            created.item = item
            return created
        }()
        entry.amountValue = amount
        entry.note = note?.isEmpty == true ? nil : note
        entry.updatedAt = .now
        apply(status, to: entry, currency: item.currency, rates: rates)
        return entry
    }

    /// Ödendi / bekliyor / hariç durumunu değiştirir. Tahmini satırlar önce kayda dönüştürülür.
    func setStatus(_ status: EntryStatus, for line: LedgerLine, rates: RateTable) {
        let entry = line.entry ?? upsertEntry(item: line.item, month: line.month, amount: line.amount,
                                              status: .pending, rates: rates)
        apply(status, to: entry, currency: line.currency, rates: rates)
        entry.updatedAt = .now
        saveIfNeeded()
    }

    /// Önceki ayda kaydı olup bu ay kaydı olmayan, düzenli olmayan kalemleri kopyalar.
    /// - Returns: Kopyalanan kayıt sayısı.
    @discardableResult
    func copyEntries(from source: Month, to target: Month, items: some Sequence<LedgerItem>, rates: RateTable) -> Int {
        var copied = 0
        for item in items where !item.isArchived && !item.isRecurring {
            guard let previous = item.entry(for: source), previous.status != .excluded,
                  item.entry(for: target) == nil else { continue }
            upsertEntry(item: item, month: target, amount: previous.amountValue, status: .pending, rates: rates)
            copied += 1
        }
        saveIfNeeded()
        return copied
    }

    private func apply(_ status: EntryStatus, to entry: LedgerEntry, currency: Currency, rates: RateTable) {
        let wasPaid = entry.status == .paid
        entry.status = status
        if status == .paid {
            if !wasPaid { entry.paidAt = .now }
            if currency != .tl, entry.rateValue == nil {
                entry.rateValue = rates.tryRate(for: currency)
            }
        } else {
            entry.paidAt = nil
            entry.rateValue = nil
        }
    }
}
