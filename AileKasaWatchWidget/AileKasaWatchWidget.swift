import WidgetKit
import SwiftUI

/// Saat kadranı komplikasyonları: sıradaki ödeme ve ayın neti. Saat uygulamasının App Group'a yazdığı özeti okur.
@main
struct AileKasaWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AileKasaWatchComplication", provider: WatchSnapshotProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Çıkı")
        .description("Sıradaki ödeme ve ayın neti.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}

struct WatchSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WatchSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSnapshotEntry {
        WatchSnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchSnapshotEntry) -> Void) {
        completion(WatchSnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSnapshotEntry>) -> Void) {
        let entry = WatchSnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}

struct ComplicationView: View {
    let entry: WatchSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        let next = snapshot?.upcoming.first
        let hidden = snapshot?.isPrivate ?? false

        switch family {
        case .accessoryInline:
            if let next {
                Text(verbatim: "\(next.title) · \(dueText(next.dueDate))")
            } else {
                Text("Çıkı")
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "creditcard.fill").font(.caption)
                Text(verbatim: next.map { dueText($0.dueDate) } ?? "—")
                    .font(.caption2.weight(.semibold))
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
        case .accessoryCorner:
            Image(systemName: "creditcard.fill")
                .widgetLabel {
                    Text(verbatim: next.map { "\($0.title) · \(dueText($0.dueDate))" } ?? "Çıkı")
                }
        default:
            VStack(alignment: .leading, spacing: 1) {
                if let next {
                    Text(verbatim: "\(next.title) · \(dueText(next.dueDate))")
                        .font(.headline)
                        .lineLimit(1)
                    Text(verbatim: hidden ? String(localized: "Tutar gizli") : next.amount)
                        .privacySensitive()
                } else {
                    Text(verbatim: snapshot?.monthTitle ?? "Çıkı").font(.headline)
                    Text("Bu ay bekleyen ödeme yok")
                }
                if let snapshot, !hidden {
                    Text(verbatim: "\(snapshot.monthTitle): \(snapshot.net)")
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: entry.date) { return String(localized: "Bugün") }
        if date < calendar.startOfDay(for: entry.date) { return String(localized: "Gecikti") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Yarın")
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
