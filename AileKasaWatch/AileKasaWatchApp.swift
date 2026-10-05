import SwiftUI

@main
struct AileKasaWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    /// DEBUG'da "-watchPage 1" ile Ödemeler sayfasından açılır (ekran görüntüsü için).
    @State private var page = UserDefaults.standard.integer(forKey: "watchPage")

    var body: some View {
        NavigationStack {
            if let snapshot = store.snapshot {
                if snapshot.isPrivate {
                    PrivateView()
                } else {
                    TabView(selection: $page) {
                        SummaryPage(snapshot: snapshot).tag(0)
                        PaymentsPage().tag(1)
                    }
                    .tabViewStyle(.verticalPage)
                }
            } else {
                WaitingView()
            }
        }
    }
}

// MARK: - Özet

private struct SummaryPage: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ay sonu net")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(verbatim: snapshot.net)
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(snapshot.netIsNegative ? WatchColors.gider : WatchColors.gelir)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Divider()
                AmountRow(title: "Gelir + alacak", value: snapshot.incoming, color: WatchColors.gelir)
                AmountRow(title: "Gider", value: snapshot.expense, color: WatchColors.gider)
                AmountRow(title: "Ödenmemiş", value: snapshot.unpaid, color: .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(verbatim: snapshot.monthTitle))
    }
}

private struct AmountRow: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ödemeler

private struct PaymentsPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            if store.upcoming.isEmpty {
                Text("Bu ay bekleyen ödeme yok")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.upcoming) { payment in
                NavigationLink {
                    PaymentDetail(payment: payment)
                } label: {
                    PaymentRow(payment: payment)
                }
            }
        }
        .navigationTitle("Ödemeler")
    }
}

private struct PaymentRow: View {
    let payment: WidgetSnapshot.Payment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: payment.title)
                .font(.headline)
                .lineLimit(2)
            Text(verbatim: payment.amount)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchColors.gider)
            Text(verbatim: "\(DueText.text(for: payment.dueDate)) · \(payment.owner)")
                .font(.caption2)
                .foregroundStyle(DueText.isUrgent(payment.dueDate) ? WatchColors.uyari : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PaymentDetail: View {
    let payment: WidgetSnapshot.Payment
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: payment.title).font(.headline)
                Text(verbatim: payment.amount)
                    .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(WatchColors.gider)
                Text(verbatim: "\(DueText.text(for: payment.dueDate)) · \(payment.owner)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    store.markPaid(payment)
                    dismiss()
                } label: {
                    Label("Ödendi", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchColors.gelir)
                .disabled(payment.key == nil)
                .padding(.top, 6)
                Text("İşaret iPhone'a gönderilir. iPhone yakında değilse bağlanınca iletilir.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Durumlar

private struct WaitingView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundStyle(WatchColors.petrol)
                .accessibilityHidden(true)
            Text("iPhone'da Aile Kasası'nı açın")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Veriler iPhone'dan gelir.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct PrivateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(WatchColors.petrol)
                .accessibilityHidden(true)
            Text("Tutarlar gizli")
                .font(.headline)
            Text("iPhone'da uygulama kilidi açık olduğu için saatte tutar gösterilmez.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

enum WatchColors {
    // Saat her zaman koyu zeminde; koyu mod tonları kullanılır.
    static let petrol = Color(red: 0x43 / 255, green: 0xB5 / 255, blue: 0xA9 / 255)
    static let gelir = Color(red: 0x4C / 255, green: 0xC4 / 255, blue: 0x8A / 255)
    static let gider = Color(red: 0xF0 / 255, green: 0x73 / 255, blue: 0x6A / 255)
    static let uyari = Color(red: 0xF0 / 255, green: 0xB0 / 255, blue: 0x4A / 255)
}

enum DueText {
    static func text(for date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Bugün") }
        if date < calendar.startOfDay(for: now) { return String(localized: "Gecikti") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Yarın")
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func isUrgent(_ date: Date, now: Date = .now) -> Bool {
        date < Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
    }
}

#Preview {
    WatchRootView()
        .environment(WatchStore())
}
