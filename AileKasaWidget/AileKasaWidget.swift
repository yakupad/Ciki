import WidgetKit
import SwiftUI

@main
struct AileKasaWidgetBundle: WidgetBundle {
    var body: some Widget {
        SummaryWidget()
    }
}

struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AileKasaSummary", provider: SnapshotProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Aile Kasası")
        .description("Bu ayın neti ve yaklaşan ödemeler.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Zaman çizelgesi

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load() ?? .placeholder))
    }

    /// Veri uygulama tarafından yazılır; widget gece yarısı "Bugün / Yarın" etiketlerini yenilemek için güncellenir.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}

// MARK: - Görünümler

enum WidgetColors {
    static let background = Color(light: 0xF3F5F2, dark: 0x0D1312)
    static let petrol = Color(light: 0x0E5F59, dark: 0x43B5A9)
    static let gelir = Color(light: 0x197E4F, dark: 0x4CC48A)
    static let gider = Color(light: 0xC34035, dark: 0xF0736A)
    static let uyari = Color(light: 0x98630B, dark: 0xF0B04A)
    static let vurguUstu = Color(light: 0xFFFFFF, dark: 0x000000)
}

struct SummaryWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isPrivate {
            switch family {
            case .systemMedium: MediumView(snapshot: snapshot, now: entry.date)
            case .accessoryRectangular: RectangularView(snapshot: snapshot, now: entry.date)
            case .accessoryInline: InlineView(snapshot: snapshot, now: entry.date)
            default: SmallView(snapshot: snapshot, now: entry.date)
            }
        } else {
            LockedView(isEmpty: entry.snapshot == nil)
        }
    }
}

private struct SmallView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: snapshot.monthTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Ay sonu net")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: snapshot.net)
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(snapshot.netIsNegative ? WidgetColors.gider : WidgetColors.gelir)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .privacySensitive()
            Spacer(minLength: 0)
            if let next = snapshot.upcoming.first {
                VStack(alignment: .leading, spacing: 2) {
                    DueLabel(date: next.dueDate, now: now)
                    Text(verbatim: next.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: next.amount)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(WidgetColors.gider)
                        .privacySensitive()
                }
            } else {
                Text("Bu ay bekleyen ödeme yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: snapshot.monthTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: snapshot.net)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(snapshot.netIsNegative ? WidgetColors.gider : WidgetColors.gelir)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .privacySensitive()
                Spacer(minLength: 0)
                Text("Ödenmemiş: \(snapshot.unpaid)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sıradaki ödemeler")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if snapshot.upcoming.isEmpty {
                    Text("Bu ay bekleyen ödeme yok")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(snapshot.upcoming.prefix(3).enumerated()), id: \.offset) { _, payment in
                    HStack(spacing: 6) {
                        DueLabel(date: payment.dueDate, now: now)
                        Text(verbatim: payment.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: payment.amount)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(WidgetColors.gider)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RectangularView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next = snapshot.upcoming.first {
                Text(verbatim: "\(next.title) · \(DueLabel.text(for: next.dueDate, now: now))")
                    .font(.headline)
                    .lineLimit(1)
                Text(verbatim: next.amount)
                    .privacySensitive()
                Text(verbatim: "\(snapshot.monthTitle): \(snapshot.net)")
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            } else {
                Text(verbatim: snapshot.monthTitle).font(.headline)
                Text(verbatim: snapshot.net).privacySensitive()
                Text("Bu ay bekleyen ödeme yok").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        if let next = snapshot.upcoming.first {
            Text(verbatim: "\(next.title) · \(DueLabel.text(for: next.dueDate, now: now))")
        } else {
            Text(verbatim: "\(snapshot.monthTitle) \(snapshot.net)")
        }
    }
}

private struct LockedView: View {
    let isEmpty: Bool
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryInline {
            Text("Aile Kasası")
        } else {
            VStack(spacing: 6) {
                Image(systemName: isEmpty ? "tray" : "lock.fill")
                    .font(.title3)
                    .foregroundStyle(WidgetColors.petrol)
                Text(isEmpty ? "Verileri görmek için uygulamayı açın" : "Tutarları görmek için uygulamayı açın")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "BUGÜN", "YARIN", "GECİKTİ" ya da "7 EKİ".
struct DueLabel: View {
    let date: Date
    let now: Date

    var body: some View {
        let isUrgent = Calendar.current.isDate(date, inSameDayAs: now) || date < Calendar.current.startOfDay(for: now)
        Text(verbatim: Self.text(for: date, now: now).uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(isUrgent ? WidgetColors.uyari : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(isUrgent ? WidgetColors.vurguUstu : Color.secondary)
    }

    static func text(for date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Bugün") }
        if date < calendar.startOfDay(for: now) { return String(localized: "Gecikti") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Yarın")
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

#Preview(as: .systemMedium) {
    SummaryWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder)
}
