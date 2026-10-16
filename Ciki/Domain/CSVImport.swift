import CoreData
import Foundation

/// "Kayıt listesi" biçimindeki CSV'yi (`CSVExport.entries`) geri okur. Aynı dosya iki kez içe aktarılırsa
/// kalemler yinelenmez: kişi, kalem, banka, tür ve para birimi aynı olan kalemin o aydaki kaydı güncellenir.
enum CSVImport {
    nonisolated struct Row: Equatable, Sendable {
        var line: Int
        var month: Month
        /// Boşsa ya da "Ortak" ise kalem ortaktır.
        var person: String?
        var title: String
        var bank: String?
        var kind: ItemKind
        var direction: Direction
        var currency: Currency
        /// Dosyadaki işaretli tutar: giderler eksi.
        var signedAmount: Decimal
        var status: EntryStatus
        var paidAt: Date?
        var rate: Decimal?
        var note: String?
        var dueDay: Int16?
    }

    nonisolated struct Parsed: Sendable {
        var rows: [Row]
        /// Okunamayan satırların dosyadaki numaraları (başlık 1. satır).
        var skippedLines: [Int]

        var people: [String] {
            var seen: [String] = []
            for name in rows.compactMap(\.person) where !seen.contains(name) { seen.append(name) }
            return seen
        }

        var months: ClosedRange<Month>? {
            guard let first = rows.map(\.month).min(), let last = rows.map(\.month).max() else { return nil }
            return first...last
        }
    }

    nonisolated struct Outcome: Equatable, Sendable {
        var createdItems = 0
        var createdPeople = 0
        var entries = 0
    }

    enum ImportError: LocalizedError {
        case empty

        var errorDescription: String? {
            String(localized: "Dosyada içe aktarılacak kayıt bulunamadı. Çıkı'nın \"Kayıt listesi\" biçiminde bir CSV seçin.")
        }
    }

    // MARK: Okuma

    nonisolated static func parse(_ text: String) throws -> Parsed {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let firstLine = body.prefix { $0 != "\n" && $0 != "\r" }
        // Türkçe dışa aktarım ";" ve ondalık ",", İngilizce "," ve ondalık "." kullanır.
        let semicolon = firstLine.filter { $0 == ";" }.count >= firstLine.filter { $0 == "," }.count
        let separator: Character = semicolon ? ";" : ","
        let decimal: Character = semicolon ? "," : "."

        let records = split(body, separator: separator)
        var parsed = Parsed(rows: [], skippedLines: [])
        for (index, fields) in records.enumerated().dropFirst() {
            guard fields.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }
            if let row = row(fields, line: index + 1, decimal: decimal) {
                parsed.rows.append(row)
            } else {
                parsed.skippedLines.append(index + 1)
            }
        }
        guard !parsed.rows.isEmpty else { throw ImportError.empty }
        return parsed
    }

    /// Sütunlar: Ay, Kişi, Kalem, Banka, Tür, Yön, Para birimi, Tutar, Durum, Ödeme tarihi, Kur, Karşılık, Not, Son ödeme günü.
    nonisolated private static func row(_ fields: [String], line: Int, decimal: Character) -> Row? {
        func field(_ index: Int) -> String {
            index < fields.count ? fields[index].trimmingCharacters(in: .whitespaces) : ""
        }
        guard let month = month(field(0)),
              let amount = number(field(7), decimal: decimal),
              let kind = match(field(4), in: ItemKind.allCases, title: \.title, raw: \.rawValue),
              let direction = match(field(5), in: Direction.allCases, title: \.title, raw: \.rawValue)
        else { return nil }

        let person = field(1)
        let title = field(2)
        let currency = field(6).isEmpty ? Currency.tl : Currency(code: field(6))
        let status = field(8).isEmpty ? .pending
            : match(field(8), in: EntryStatus.allCases, title: \.title, raw: \.rawValue)
        guard let status else { return nil }

        return Row(line: line, month: month,
                   person: person.isEmpty || person == String(localized: "Ortak") ? nil : person,
                   title: title == kind.title ? "" : title,
                   bank: field(3).isEmpty ? nil : Banks.canonical(field(3)),
                   kind: kind, direction: direction, currency: currency,
                   signedAmount: amount, status: status,
                   paidAt: date(field(9)), rate: number(field(10), decimal: decimal),
                   note: field(12).isEmpty ? nil : field(12),
                   dueDay: Int16(field(13)).flatMap { (1...31).contains($0) ? $0 : nil })
    }

    /// "2026-10" biçimindeki ay.
    nonisolated private static func month(_ text: String) -> Month? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]), parts[0] > 1900 else { return nil }
        return Month(year: parts[0], month: parts[1])
    }

    /// Gruplama ayracı ve boşluklar atılır; ondalık ayraç noktaya çevrilir.
    nonisolated static func number(_ text: String, decimal: Character) -> Decimal? {
        let grouping: Character = decimal == "," ? "." : ","
        let cleaned = String(text.filter { !$0.isWhitespace && $0 != grouping && $0 != "\u{00A0}" })
            .replacingOccurrences(of: String(decimal), with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated private static func date(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        return try? Date(text, strategy: .iso8601.year().month().day())
    }

    nonisolated private static func match<T>(_ text: String, in cases: [T], title: (T) -> String, raw: (T) -> String) -> T? {
        let target = Banks.key(text)
        return cases.first { Banks.key(title($0)) == target || Banks.key(raw($0)) == target }
    }

    /// Tırnaklı alanları (içinde ayraç, satır sonu ya da "" olabilir) destekleyen CSV bölücü.
    nonisolated static func split(_ text: String, separator: Character) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                quoted = true
            } else if character == separator {
                fields.append(field)
                field = ""
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                fields.append(field)
                records.append(fields)
                fields = []
                field = ""
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !fields.isEmpty {
            fields.append(field)
            records.append(fields)
        }
        return records
    }

    // MARK: Yazma

    /// Satırları haneye ekler ve kaydeder.
    @discardableResult
    static func apply(_ rows: [Row], to context: NSManagedObjectContext, rates: RateTable) -> Outcome {
        let household = context.currentHousehold()
        var outcome = Outcome()
        var people: [String: Person] = [:]
        for person in household.peopleArray { people[Banks.key(person.displayName)] = person }
        var items: [String: LedgerItem] = [:]
        for item in household.itemsArray { items[key(item)] = item }

        for row in rows {
            var owner: Person?
            if let name = row.person {
                if let existing = people[Banks.key(name)] {
                    owner = existing
                } else {
                    let created = context.addPerson(named: name, to: household)
                    people[Banks.key(name)] = created
                    outcome.createdPeople += 1
                    owner = created
                }
            }

            let itemKey = key(owner: owner, title: row.title, bank: row.bank, kind: row.kind, currency: row.currency)
            let item = items[itemKey] ?? {
                let created = LedgerItem(context: context)
                context.place(created, in: household)
                created.uuid = UUID()
                created.createdAt = .now
                created.household = household
                created.owner = owner
                created.name = row.title.isEmpty ? nil : row.title
                created.bank = row.bank
                created.kind = row.kind
                created.direction = row.direction
                created.currency = row.currency
                created.sortOrder = context.nextItemSortOrder()
                items[itemKey] = created
                outcome.createdItems += 1
                return created
            }()
            if let dueDay = row.dueDay { item.dueDay = dueDay }
            item.updatedAt = .now
            item.updatedBy = DeviceOwner.name(in: context)

            let entry = context.upsertEntry(item: item, month: row.month, amount: row.signedAmount * item.direction.sign,
                                            status: row.status, note: row.note, rates: rates)
            if row.status == .paid {
                if let paidAt = row.paidAt { entry.paidAt = paidAt }
                if let rate = row.rate, item.currency != .tl { entry.rateValue = rate }
            }
            outcome.entries += 1
        }
        context.saveIfNeeded()
        return outcome
    }

    private static func key(_ item: LedgerItem) -> String {
        key(owner: item.owner, title: item.name ?? "", bank: item.bankName, kind: item.kind, currency: item.currency)
    }

    private static func key(owner: Person?, title: String, bank: String?, kind: ItemKind, currency: Currency) -> String {
        [owner.map { Banks.key($0.displayName) } ?? "", Banks.key(title), Banks.key(bank ?? ""), kind.rawValue, currency.code]
            .joined(separator: "|")
    }
}
