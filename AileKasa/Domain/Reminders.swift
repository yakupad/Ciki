import Foundation
import Observation
import UserNotifications
import CoreData

/// Son ödeme gününden önce gönderilecek yerel bildirim.
struct Reminder: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
}

enum Reminders {
    static let idPrefix = "due-"
    /// iOS en fazla 64 bekleyen bildirime izin verir.
    static let limit = 60

    /// Bekleyen giderler için hatırlatma tarihleri. Geçmişte kalanlar atlanır.
    static func plan(lines: [LedgerLine], daysBefore: Int, hour: Int, now: Date = .now,
                     calendar: Calendar = .current) -> [Reminder] {
        lines.compactMap { line -> Reminder? in
            guard line.direction == .expense, line.status == .pending, line.amount > 0,
                  line.item.dueDay > 0 else { return nil }
            let day = line.month.clampedDay(Int(line.item.dueDay))
            guard let due = calendar.date(from: DateComponents(year: line.month.year, month: line.month.month, day: day)),
                  let fireDay = calendar.date(byAdding: .day, value: -daysBefore, to: due),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: fireDay),
                  fire > now else { return nil }

            let amount = Money.string(line.amount * line.direction.sign, currency: line.currency)
            let dueText = due.formatted(.dateTime.day().month(.wide).locale(Money.locale))
            let body = daysBefore == 0
                ? String(localized: "Son ödeme bugün · \(amount) · \(line.item.ownerName)")
                : String(localized: "Son ödeme \(dueText) · \(amount) · \(line.item.ownerName)")
            let id = "\(idPrefix)\(line.item.objectID.uriRepresentation().absoluteString)-\(line.month.key)"
            return Reminder(id: id, date: fire, title: line.item.fullTitle, body: body)
        }
        .sorted { $0.date < $1.date }
        .prefix(limit)
        .map { $0 }
    }
}

/// Hatırlatma ayarları ve bildirimlerin yeniden planlanması.
@Observable
final class ReminderScheduler {
    private(set) var isEnabled: Bool
    var daysBefore: Int {
        didSet { defaults.set(daysBefore, forKey: "reminders.daysBefore") }
    }
    var hour: Int {
        didSet { defaults.set(hour, forKey: "reminders.hour") }
    }
    private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: "reminders.enabled")
        self.daysBefore = defaults.object(forKey: "reminders.daysBefore") as? Int ?? 1
        self.hour = defaults.object(forKey: "reminders.hour") as? Int ?? 9
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else {
                errorMessage = String(localized: "Bildirim izni verilmedi. iOS Ayarlar → Bildirimler → Aile Kasası'ndan açabilirsiniz.")
                isEnabled = false
                defaults.set(false, forKey: "reminders.enabled")
                return
            }
            errorMessage = nil
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: "reminders.enabled")
    }

    /// Bu ay ve sonraki iki ayın bekleyen ödemeleri için bildirimleri baştan kurar.
    func reschedule(context: NSManagedObjectContext, rates: RateTable) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Reminders.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled else { return }

        let request = NSFetchRequest<LedgerItem>(entityName: "LedgerItem")
        request.predicate = NSPredicate(format: "isArchived == NO")
        let items = (try? context.fetch(request)) ?? []
        let now = Month.current
        let lines = (0...2).flatMap { Ledger.lines(for: now.adding($0), items: items, rates: rates) }

        for reminder in Reminders.plan(lines: lines, daysBefore: daysBefore, hour: hour) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
