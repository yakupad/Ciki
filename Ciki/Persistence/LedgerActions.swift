import CoreData

extension NSManagedObjectContext {
    /// Kalemin o aydaki kaydını oluşturur ya da günceller.
    @discardableResult
    func upsertEntry(item: LedgerItem, month: Month, amount: Decimal,
                     status: EntryStatus, note: String? = nil, rates: RateTable) -> LedgerEntry {
        let entry = item.entry(for: month) ?? {
            let created = LedgerEntry(context: self)
            place(created, in: item.household)
            created.uuid = UUID()
            created.createdAt = .now
            created.monthKey = month.key
            created.item = item
            return created
        }()
        entry.amountValue = amount
        entry.note = note?.isEmpty == true ? nil : note
        entry.updatedAt = .now
        entry.updatedBy = DeviceOwner.name(in: self)
        apply(status, to: entry, currency: item.currency, rates: rates)
        return entry
    }

    /// Ödendi / bekliyor / hariç durumunu değiştirir. Tahmini satırlar önce kayda dönüştürülür.
    func setStatus(_ status: EntryStatus, for line: LedgerLine, rates: RateTable) {
        let entry = line.entry ?? upsertEntry(item: line.item, month: line.month, amount: line.amount,
                                              status: .pending, rates: rates)
        apply(status, to: entry, currency: line.currency, rates: rates)
        entry.updatedAt = .now
        entry.updatedBy = DeviceOwner.name(in: self)
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

    /// Kısmi ödeme ekler. Ödenenler kalanı kapatırsa kayıt ödendi olur.
    @discardableResult
    func addPayment(_ amount: Decimal, on date: Date = .now, to line: LedgerLine, rates: RateTable) -> LedgerEntry {
        let entry = line.entry ?? upsertEntry(item: line.item, month: line.month, amount: line.amount,
                                              status: .pending, rates: rates)
        if entry.status == .excluded { apply(.pending, to: entry, currency: line.currency, rates: rates) }
        entry.paymentList.append(EntryPayment(date: date, amount: amount))
        if entry.status == .pending, entry.remainingValue <= 0 {
            apply(.paid, to: entry, currency: line.currency, rates: rates)
            entry.paidAt = date
        }
        touch(entry)
        saveIfNeeded()
        return entry
    }

    /// Kısmi ödemeyi siler; ödendi görünen kayıt kalan çıkarsa bekliyora döner.
    func removePayment(_ payment: EntryPayment, from entry: LedgerEntry, rates: RateTable) {
        entry.paymentList.removeAll { $0.id == payment.id }
        if entry.status == .paid, entry.paymentList.reduce(0, { $0 + $1.amount }) < entry.dueValue {
            apply(.pending, to: entry, currency: entry.item?.currency ?? .tl, rates: rates)
        }
        touch(entry)
        saveIfNeeded()
    }

    /// Önceki bir ayın ödenmeyen kalanını hedef aya taşır. Kaynak ayda kalan düşer, hedef ayın kaydına eklenir;
    /// böylece tutar iki ayda birden sayılmaz.
    func carryOver(_ line: LedgerLine, to target: Month, rates: RateTable) {
        guard let source = line.entry, source.month < target, source.remainingValue > 0, let item = source.item else { return }
        if source.carriedToKey != 0, source.carriedToKey != target.key { undoCarry(of: source, rates: rates, save: false) }
        let moved = source.remainingValue
        let destination = item.entry(for: target) ?? upsertEntry(
            item: item, month: target, amount: item.isRecurringActive(in: target) ? (item.recurringAmount(in: target) ?? 0) : 0,
            status: .pending, rates: rates)
        source.carriedOutValue += moved
        source.carriedToKey = target.key
        destination.carriedInValue += moved
        if destination.status == .paid { apply(.pending, to: destination, currency: item.currency, rates: rates) }
        touch(source)
        touch(destination)
        saveIfNeeded()
    }

    /// Devri geri alır: tutar kaynak aya döner. Yalnızca devir için açılmış boş hedef kaydı silinir.
    func undoCarry(of source: LedgerEntry, rates: RateTable, save: Bool = true) {
        guard source.carriedToKey != 0, let item = source.item else { return }
        if let destination = item.entry(for: Month(key: source.carriedToKey)) {
            destination.carriedInValue = max(destination.carriedInValue - source.carriedOutValue, 0)
            if destination.amountValue == 0, destination.carriedInValue == 0, destination.paymentList.isEmpty,
               destination.status != .paid {
                delete(destination)
            } else {
                touch(destination)
            }
        }
        source.carriedOutValue = 0
        source.carriedToKey = 0
        touch(source)
        if save { saveIfNeeded() }
    }

    /// Kaydı siler. Bu kayda devredilmiş kalanlar kaynak aylarına geri döner.
    func deleteEntry(_ entry: LedgerEntry, rates: RateTable) {
        if entry.carriedInValue > 0, let item = entry.item {
            for source in item.entriesArray where source.carriedToKey == entry.monthKey && source != entry {
                source.carriedOutValue = 0
                source.carriedToKey = 0
                touch(source)
            }
        }
        if entry.carriedToKey != 0 { undoCarry(of: entry, rates: rates, save: false) }
        delete(entry)
        saveIfNeeded()
    }

    private func touch(_ entry: LedgerEntry) {
        entry.updatedAt = .now
        entry.updatedBy = DeviceOwner.name(in: self)
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
