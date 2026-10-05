import CoreData
import UserNotifications
import WidgetKit

/// "Tüm verilerimi sil": bu cihazdaki (ve iCloud açıksa kendi iCloud'umuzdaki) haneyi siler,
/// cihaza özel ayarları sıfırlar. Eşin paylaştığı hane silinmez; ondan ayrılmak paylaşım ekranından yapılır.
enum DataEraser {
    static func eraseOwnData(in context: NSManagedObjectContext) {
        let request = NSFetchRequest<Household>(entityName: "Household")
        for household in (try? context.fetch(request)) ?? [] where !household.isInSharedStore {
            context.delete(household)
        }
        context.saveIfNeeded()

        let defaults = UserDefaults.standard
        for key in [DeviceOwner.key, OnboardingView.completedKey] {
            defaults.removeObject(forKey: key)
        }
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.removePersistentDomain(forName: WidgetSnapshot.appGroup)
        WidgetCenter.shared.reloadAllTimelines()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
