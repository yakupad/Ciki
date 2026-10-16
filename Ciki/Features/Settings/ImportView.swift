import SwiftUI
import UniformTypeIdentifiers

/// "Kayıt listesi" biçimindeki bir CSV'yi okur, özetini gösterir ve onaylanınca haneye ekler.
struct ImportView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(RateService.self) private var rates

    @State private var isPicking = false
    @State private var parsed: CSVImport.Parsed?
    @State private var fileName: String?
    @State private var outcome: CSVImport.Outcome?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button("CSV dosyası seç", systemImage: "doc.badge.plus") { isPicking = true }
            } footer: {
                Text("Çıkı'nın \"Kayıt listesi\" biçimi: ay (2026-10), kişi, kalem, banka, tür, yön, para birimi, tutar, durum ve isteğe bağlı olarak ödeme tarihi, kur, not, son ödeme günü. Aynı kalemin aynı aydaki kaydı varsa güncellenir; kalemler yinelenmez.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(Color.gider)
                }
            }

            if let parsed {
                Section {
                    if let fileName {
                        LabeledContent("Dosya", value: fileName)
                    }
                    LabeledContent("Kayıt", value: parsed.rows.count.formatted())
                    if let months = parsed.months {
                        LabeledContent("Aylar", value: "\(months.lowerBound.title) – \(months.upperBound.title)")
                    }
                    if !parsed.people.isEmpty {
                        LabeledContent("Kişiler", value: parsed.people.formatted(.list(type: .and)))
                    }
                    if !parsed.skippedLines.isEmpty {
                        Text("Okunamayan satırlar atlanacak: \(parsed.skippedLines.map(String.init).joined(separator: ", "))")
                            .foregroundStyle(Color.uyari)
                    }
                    Button("İçe aktar", systemImage: "square.and.arrow.down") {
                        outcome = CSVImport.apply(parsed.rows, to: context, rates: rates.table)
                        self.parsed = nil
                    }
                } header: {
                    Text("Önizleme")
                }
            }

            if let outcome {
                Section {
                    Label("\(outcome.entries) kayıt içe aktarıldı. \(outcome.createdItems) yeni kalem, \(outcome.createdPeople) yeni kişi eklendi.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.gelir)
                }
            }
        }
        .navigationTitle("İçe aktar")
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            load(result)
        }
    }

    private func load(_ result: Result<URL, Error>) {
        outcome = nil
        parsed = nil
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            parsed = try CSVImport.parse(text)
            fileName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
