import SwiftUI
import CoreData

/// Kalemin solundaki rozet: banka baş harfleri ya da tür simgesi.
struct ItemBadge: View {
    /// Nesne izlenir: başka cihazdan iCloud ile gelen değişiklikte satır kendiliğinden yenilenir.
    @ObservedObject var item: LedgerItem
    /// Yazı boyutuyla birlikte büyür (Dynamic Type).
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    init(item: LedgerItem) {
        self._item = ObservedObject(wrappedValue: item)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(background)
            if let bank = item.bankName {
                Text(Banks.initials(for: bank))
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            } else if item.currency != .tl {
                Text(item.currency.symbol)
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var background: Color {
        if let bank = item.bankName { return Color(hex: Banks.colorHex(for: bank)) }
        switch item.direction {
        case .income: return item.owner?.color ?? .gelir
        case .receivable: return .petrol
        case .expense: return item.currency == .tl ? Color(hex: 0x4A5A55) : Color(hex: 0x3E7C6F)
        }
    }
}

/// "SÖT 5" / "BUGÜN" / "GECİKTİ" çipi.
struct DueChip: View {
    let day: Int
    let month: Month
    var today: Date = .now

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(foreground)
    }

    private var state: Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: today)
        let todayMonth = Month(year: parts.year ?? 0, month: parts.month ?? 1)
        if month < todayMonth { return -1 }
        if month > todayMonth { return 1 }
        let dueDay = month.clampedDay(day)
        let current = parts.day ?? 1
        return dueDay < current ? -1 : (dueDay == current ? 0 : 1)
    }

    private var label: String {
        switch state {
        case -1: String(localized: "GECİKTİ")
        case 0: String(localized: "BUGÜN")
        default: "\(month.clampedDay(day)) \(month.shortName.uppercased(with: Money.locale))"
        }
    }

    private var background: Color {
        switch state {
        case -1: .gider
        case 0: .uyari
        default: Color(.tertiarySystemFill)
        }
    }

    private var foreground: Color {
        state == 1 ? .ikincil : .vurguUstu
    }
}

/// Önceki / sonraki ay düğmeleri ve bugüne dönüş.
struct MonthNavigator: ToolbarContent {
    @Binding var month: Month

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if month != .current {
                Button("Bugün") { month = .current }
            }
            Button("Önceki ay", systemImage: "chevron.left") { month = month.adding(-1) }
            Button("Sonraki ay", systemImage: "chevron.right") { month = month.adding(1) }
        }
    }
}

/// Bir ay seçici satır: "Başlangıç   ‹ Ekim 2026 ›"
struct MonthStepperRow: View {
    let title: LocalizedStringKey
    @Binding var month: Month

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button("Önceki ay", systemImage: "chevron.left") { month = month.adding(-1) }
                .labelStyle(.iconOnly)
            Text(month.title)
                .monospacedDigit()
                .frame(minWidth: 96)
            Button("Sonraki ay", systemImage: "chevron.right") { month = month.adding(1) }
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
    }
}

enum OwnerFilter: Hashable {
    case all
    case shared
    case person(NSManagedObjectID)

    func includes(_ item: LedgerItem) -> Bool {
        switch self {
        case .all: true
        case .shared: item.owner == nil
        case .person(let id): item.owner?.objectID == id
        }
    }
}

struct OwnerFilterPicker: View {
    @Binding var selection: OwnerFilter
    let people: [Person]

    var body: some View {
        // Tümü + kişiler + Ortak beş seçeneği geçerse bölümlü seçici sıkışır; menüye geçilir.
        if people.count <= 3 {
            picker.pickerStyle(.segmented)
        } else {
            HStack {
                Text("Kişi").foregroundStyle(Color.ikincil)
                Spacer()
                picker.pickerStyle(.menu)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.kart, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var picker: some View {
        pickerBody
            // Seçili kişi silinirse filtre "Tümü"ne döner.
            .onChange(of: people.map(\.objectID)) { _, ids in
                if case .person(let id) = selection, !ids.contains(id) { selection = .all }
            }
    }

    private var pickerBody: some View {
        Picker("Kişi", selection: $selection) {
            Text("Tümü").tag(OwnerFilter.all)
            ForEach(people, id: \.objectID) { person in
                Text(verbatim: person.displayName).tag(OwnerFilter.person(person.objectID))
            }
            Text("Ortak").tag(OwnerFilter.shared)
        }
    }
}

/// Kayıt ve kalem düzenleme sayfaları için yönlendirme.
enum EditorRoute: Identifiable {
    case entry(item: LedgerItem?, month: Month)
    case newItem
    case item(LedgerItem)
    case settings

    var id: String {
        switch self {
        case .entry(let item, let month): "entry-\(item?.objectID.uriRepresentation().absoluteString ?? "new")-\(month.key)"
        case .newItem: "new-item"
        case .item(let item): "item-\(item.objectID.uriRepresentation().absoluteString)"
        case .settings: "settings"
        }
    }
}

struct EditorSheet: View {
    let route: EditorRoute

    var body: some View {
        switch route {
        case .entry(let item, let month):
            EntryEditorView(item: item, month: month)
        case .newItem:
            ItemEditorView(item: nil)
        case .item(let item):
            ItemEditorView(item: item)
        case .settings:
            SettingsView()
        }
    }
}
