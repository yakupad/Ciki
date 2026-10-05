import Foundation
import Observation

/// TCMB günlük kur dosyasından döviz satış kurlarını alır ve son değeri saklar.
@Observable
final class RateService {
    private(set) var table: RateTable
    private(set) var updatedAt: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private static let url = URL(string: "https://www.tcmb.gov.tr/kurlar/today.xml")!
    private static let storageKey = "rates.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        var rates = stored.compactMapValues { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        // Eski sürümün yalnızca USD/EUR sakladığı anahtarlar.
        for code in ["USD", "EUR"] where rates[code] == nil {
            if let legacy = defaults.string(forKey: "rate.\(code)").flatMap({ Decimal(string: $0) }) {
                rates[code] = legacy
            }
        }
        self.table = RateTable(rates: rates)
        self.updatedAt = defaults.object(forKey: "rate.updatedAt") as? Date
    }

    func refreshIfStale() async {
        if let updatedAt, Date.now.timeIntervalSince(updatedAt) < 6 * 3600, table.rates.count > 2 { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.url)
            let rates = try TCMBParser.parse(data)
            guard !rates.rates.isEmpty else { throw URLError(.cannotParseResponse) }
            table = rates
            updatedAt = .now
            errorMessage = nil
            persist()
        } catch {
            errorMessage = String(localized: "Kur alınamadı. İnternet bağlantınızı kontrol edip yeniden deneyin.")
        }
    }

    private func persist() {
        let stored = table.rates.mapValues { "\($0)" }
        defaults.set(stored, forKey: Self.storageKey)
        defaults.set(updatedAt, forKey: "rate.updatedAt")
    }
}

/// `<Currency Kod="JPY"><Unit>100</Unit> … <ForexSelling>31.19</ForexSelling>` yapısını okur.
/// Döviz satış kuru yoksa efektif satış kullanılır; birden fazla birimlik kurlar (JPY 100) bire indirilir.
nonisolated final class TCMBParser: NSObject, XMLParserDelegate {
    private var currentCode: String?
    private var fields: [String: String] = [:]
    private var buffer = ""
    private var result = RateTable()

    static func parse(_ data: Data) throws -> RateTable {
        let delegate = TCMBParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "Currency" {
            currentCode = attributeDict["Kod"] ?? attributeDict["CurrencyCode"]
            fields = [:]
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if currentCode != nil {
            fields[elementName] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if elementName == "Currency", let code = currentCode {
            let posix = Locale(identifier: "en_US_POSIX")
            let unit = fields["Unit"].flatMap { Decimal(string: $0, locale: posix) } ?? 1
            let selling = [fields["ForexSelling"], fields["BanknoteSelling"]]
                .compactMap { $0 }
                .first { !$0.isEmpty }
                .flatMap { Decimal(string: $0, locale: posix) }
            if let selling, selling > 0, unit > 0, code != "XDR" {
                result.rates[code] = selling / unit
            }
            currentCode = nil
        }
        buffer = ""
    }
}
