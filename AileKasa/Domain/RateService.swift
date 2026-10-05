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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.table = RateTable(
            usd: defaults.string(forKey: "rate.USD").flatMap { Decimal(string: $0) },
            eur: defaults.string(forKey: "rate.EUR").flatMap { Decimal(string: $0) }
        )
        self.updatedAt = defaults.object(forKey: "rate.updatedAt") as? Date
    }

    func refreshIfStale() async {
        if let updatedAt, Date.now.timeIntervalSince(updatedAt) < 6 * 3600 { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.url)
            let rates = try TCMBParser.parse(data)
            guard rates.usd != nil || rates.eur != nil else { throw URLError(.cannotParseResponse) }
            table = rates
            updatedAt = .now
            errorMessage = nil
            persist()
        } catch {
            errorMessage = "Kur alınamadı. İnternet bağlantınızı kontrol edip yeniden deneyin."
        }
    }

    private func persist() {
        defaults.set(table.usd.map { "\($0)" }, forKey: "rate.USD")
        defaults.set(table.eur.map { "\($0)" }, forKey: "rate.EUR")
        defaults.set(updatedAt, forKey: "rate.updatedAt")
    }
}

/// `<Currency Kod="USD"> … <ForexSelling>41.2034</ForexSelling>` yapısını okur.
nonisolated final class TCMBParser: NSObject, XMLParserDelegate {
    private var currentCode: String?
    private var currentElement = ""
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
        }
        currentElement = elementName
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "ForexSelling", let code = currentCode {
            let value = Decimal(string: buffer.trimmingCharacters(in: .whitespacesAndNewlines),
                                locale: Locale(identifier: "en_US_POSIX"))
            switch code {
            case "USD": result.usd = value
            case "EUR": result.eur = value
            default: break
            }
        }
        if elementName == "Currency" { currentCode = nil }
        buffer = ""
    }
}
