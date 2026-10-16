import Foundation
import CloudKit
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
            lastError = Self.describe(error)
        }
    }

    /// Hatanın okunabilir açıklaması. CloudKit kısmi hatalarında (ör. şema eksikliği) asıl neden üst düzey
    /// hatada değil, kayıt başına hatalarda ve sunucu mesajındadır; o mesaj öne alınır.
    nonisolated static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if let ckError = error as? CKError {
            if let partial = ckError.partialErrorsByItemID?.values
                .first(where: { ($0 as? CKError)?.code != .batchRequestFailed }) {
                return describe(partial)
            }
            if let server = nsError.userInfo["ServerErrorDescription"] as? String, !server.isEmpty {
                return server
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           nsError.localizedFailureReason == nil {
            let detail = describe(underlying)
            if !detail.isEmpty { return detail }
        }
        return nsError.localizedFailureReason ?? nsError.localizedDescription
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
