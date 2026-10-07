import SwiftUI
import CoreData

/// Son eklenen ya da değiştirilen kayıtlar; kimin yaptığıyla birlikte, güne göre gruplu.
struct ActivityView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerEntry.updatedAt, order: .reverse)],
                  predicate: NSPredicate(format: "updatedAt != nil AND item != nil"))
    private var entries: FetchedResults<LedgerEntry>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>

    @State private var route: EditorRoute?

    var body: some View {
        let recent = Array(entries.prefix(100))
        let days = Dictionary(grouping: recent) { Calendar.current.startOfDay(for: $0.updatedAt ?? .distantPast) }
            .sorted { $0.key > $1.key }

        List {
            if recent.isEmpty {
                ContentUnavailableView("Henüz değişiklik yok", systemImage: "clock",
                                       description: Text("Kayıt ekledikçe ya da ödendi işaretledikçe burada görünür."))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            ForEach(days, id: \.key) { day, entries in
                Section {
                    ForEach(entries, id: \.objectID) { entry in
                        if let item = entry.item {
                            ActivityRow(entry: entry, item: item, color: color(for: entry.updatedBy))
                                .contentShape(Rectangle())
                                .onTapGesture { route = .entry(item: item, month: entry.month) }
                        }
                    }
                } header: {
                    Text(verbatim: dayTitle(day))
                }
            }
        }
        .navigationTitle("Son değişiklikler")
        .sheet(item: $route) { EditorSheet(route: $0) }
    }

    private func color(for name: String?) -> Color {
        guard let name else { return .secondary }
        return people.first { Banks.key($0.displayName) == Banks.key(name) }?.color ?? .secondary
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return String(localized: "Bugün") }
        if Calendar.current.isDateInYesterday(day) { return String(localized: "Dün") }
        return day.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(Money.locale))
    }
}

private struct ActivityRow: View {
    /// Nesne izlenir: başka cihazdan iCloud ile gelen değişiklikte satır kendiliğinden yenilenir.
    @ObservedObject var entry: LedgerEntry
    @ObservedObject var item: LedgerItem
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ItemBadge(item: item)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: item.fullTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(verbatim: (entry.updatedAt ?? .now).formatted(.dateTime.hour().minute().locale(Money.locale)))
                        .font(.caption)
                        .foregroundStyle(Color.ikincil)
                        .monospacedDigit()
                }
                Text(verbatim: "\(entry.month.title) · \(Money.string(entry.amountValue * item.direction.sign, currency: item.currency)) · \(entry.status.title)")
                    .font(.caption)
                    .foregroundStyle(Color.ikincil)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(verbatim: entry.updatedBy ?? String(localized: "Bilinmeyen kişi"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.updatedBy == nil ? Color.ikincil : Color.primary)
                }
            }
        }
    }
}
