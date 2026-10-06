import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Excel'de açılacak CSV dosyaları. Türkçede ayraç ";" ve ondalık ",", İngilizcede "," ve "." kullanılır.
enum CSVExport {
    struct Format {
        let separator: String
        let locale: Locale

        static var current: Format {
            AppLanguage.current == .english
                ? Format(separator: ",", locale: Locale(identifier: "en_US"))
                : Format(separator: ";", locale: Locale(identifier: "tr_TR"))
        }
    }

    /// Tüm kayıtlar, ay sırasıyla, her satır bir kayıt.
    static func entries(items: [LedgerItem], rates: RateTable, format: Format = .current) -> String {
        let header = [
            String(localized: "Ay"), String(localized: "Kişi"), String(localized: "Kalem"),
            String(localized: "Banka"), String(localized: "Tür"), String(localized: "Yön"),
            String(localized: "Para birimi"), String(localized: "Tutar"), String(localized: "Durum"),
            String(localized: "Ödeme tarihi"), String(localized: "Kur (TL)"),
            String(localized: "Karşılık (\(rates.base.code))"), String(localized: "Not"),
        ]
        let rows = items
            .flatMap { item in item.entriesArray.map { (item, $0) } }
            .sorted { ($0.1.monthKey, $0.0.sortOrder) < ($1.1.monthKey, $1.0.sortOrder) }
            .map { item, entry -> [String] in
                let line = Ledger.line(for: item, month: entry.month, rates: rates)
                return [
                    String(format: "%04d-%02d", entry.month.year, entry.month.month),
                    item.ownerName,
                    item.title,
                    item.bankName ?? "",
                    item.kind.title,
                    item.direction.title,
                    item.currency.code,
                    number(entry.amountValue * item.direction.sign, format),
                    entry.status.title,
                    entry.paidAt.map { $0.formatted(.iso8601.year().month().day()) } ?? "",
                    entry.rateValue.map { number($0, format, digits: 4) } ?? "",
                    line?.signedValue.map { number($0, format) } ?? "",
                    entry.note ?? "",
                ]
            }
        return csv([header] + rows, format)
    }

    /// Excel düzeni: satırlar kalemler, sütunlar aylar, en altta net. Tutarlar gösterim para biriminde.
    static func table(items: [LedgerItem], months: [Month], rates: RateTable, format: Format = .current) -> String {
        let header = [String(localized: "Kalem"), String(localized: "Kişi")] + months.map(\.shortTitle)
        var net = Array(repeating: Decimal(0), count: months.count)
        var rows: [[String]] = []
        for item in items {
            let lines = months.map { Ledger.line(for: item, month: $0, rates: rates) }
            guard lines.contains(where: { $0 != nil }) else { continue }
            let cells = lines.enumerated().map { index, line -> String in
                guard let line, line.counts, let value = line.signedValue else { return "" }
                net[index] += value
                return number(value, format)
            }
            rows.append([item.fullTitle, item.ownerName] + cells)
        }
        rows.append([String(localized: "Net"), ""] + net.map { number($0, format) })
        return csv([header] + rows, format)
    }

    static func number(_ value: Decimal, _ format: Format, digits: Int = 2) -> String {
        value.formatted(.number.locale(format.locale).grouping(.never).precision(.fractionLength(0...digits)))
    }

    static func csv(_ rows: [[String]], _ format: Format) -> String {
        rows.map { row in
            row.map { field in
                let needsQuotes = field.contains(format.separator) || field.contains("\"") || field.contains("\n")
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return needsQuotes ? "\"\(escaped)\"" : escaped
            }.joined(separator: format.separator)
        }.joined(separator: "\r\n")
    }
}

/// Paylaşım sayfasına verilen CSV dosyası. Excel'in Türkçe karakterleri tanıması için UTF-8 BOM eklenir.
nonisolated struct CSVFile: Transferable {
    let fileName: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.fileName)
            try ("\u{FEFF}" + file.text).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
