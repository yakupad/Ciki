import SwiftUI
import CoreData

/// Verileri Excel'de açılabilen CSV dosyaları olarak paylaşır.
struct ExportView: View {
    @Environment(RateService.self) private var rates

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerItem.sortOrder)])
    private var items: FetchedResults<LedgerItem>

    var body: some View {
        let all = Array(items)
        let entryCount = all.reduce(0) { $0 + ($1.entries?.count ?? 0) }
        let months = exportMonths(all)
        let stamp = Date.now.formatted(.iso8601.year().month().day())

        List {
            Section {
                ShareLink(item: CSVFile(fileName: "AileKasa-kayitlar-\(stamp).csv",
                                        text: CSVExport.entries(items: all, rates: rates.table)),
                          preview: SharePreview(String(localized: "Kayıt listesi"))) {
                    Label("Kayıt listesi", systemImage: "list.bullet.rectangle")
                }
            } footer: {
                Text("Her satır bir kayıt: ay, kişi, kalem, banka, tutar, durum, ödeme tarihi ve kur. Toplam \(entryCount) kayıt.")
            }

            Section {
                ShareLink(item: CSVFile(fileName: "AileKasa-tablo-\(stamp).csv",
                                        text: CSVExport.table(items: all, months: months, rates: rates.table)),
                          preview: SharePreview(String(localized: "Aylık tablo"))) {
                    Label("Aylık tablo (Excel düzeni)", systemImage: "tablecells")
                }
            } footer: {
                if let first = months.first, let last = months.last {
                    Text("Eski Excel tablonuz gibi: satırlar kalemler, sütunlar aylar (\(first.title) – \(last.title)). Tutarlar \(rates.table.base.title) cinsinden; düzenli kalemlerin tahminleri dahil, hariç kayıtlar boş.")
                }
            }
        }
        .navigationTitle("Dışa aktar")
    }

    /// İlk kaydın ayından (en fazla 24 ay geriye) bugünden 6 ay sonrasına.
    private func exportMonths(_ items: [LedgerItem]) -> [Month] {
        let now = Month.current
        let earliest = items.flatMap(\.entriesArray).map(\.month).min() ?? now
        let start = max(earliest, now.adding(-24))
        return (0...start.distance(to: now.adding(6))).map { start.adding($0) }
    }
}
