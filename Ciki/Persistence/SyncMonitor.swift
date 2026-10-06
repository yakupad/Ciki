import Foundation
import Observation

/// iCloud eşitlemesinin son durumu: Ayarlar'da gösterilir.
@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    /// Son başarılı içe ya da dışa aktarma.
    private(set) var lastSuccess: Date?
    /// Son başarısız olayın açıklaması; sonra başarılı bir olay gelirse temizlenir.
    private(set) var lastError: String?

    func record(success: Bool, error: Error?) {
        if success {
            lastSuccess = .now
            lastError = nil
        } else if let error {
            lastError = (error as NSError).localizedFailureReason ?? error.localizedDescription
        }
    }

    /// Bu derleme hangi iCloud ortamına bağlı. Xcode'dan kurulanlar Development'a,
    /// TestFlight ve App Store derlemeleri Production'a bağlanır; ikisi birbirini görmez.
    static var isDevelopmentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
