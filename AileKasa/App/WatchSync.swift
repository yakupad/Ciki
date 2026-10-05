#if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
import CoreData
import WatchConnectivity

/// iPhone ↔ Apple Watch: özeti saate gönderir, saatten gelen "ödendi" işaretlerini işler.
/// WCSession temsilci metotları arka plan kuyruğunda çağrılır; işler ana aktöre aktarılır.
nonisolated final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    static let snapshotKey = "snapshot"
    static let markPaidKey = "markPaid"

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Son özet, saat uygulaması açılmasa da bir sonraki açılışında hazır olsun diye uygulama bağlamı olarak gider.
    func send(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = snapshot.encoded() else { return }
        try? session.updateApplicationContext([Self.snapshotKey: data])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, let snapshot = WidgetSnapshot.load() else { return }
        send(snapshot)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Kullanıcı başka bir saate geçtiyse yeni saatle oturumu yeniden aç.
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    private func handle(_ payload: [String: Any]) {
        guard let key = payload[Self.markPaidKey] as? String else { return }
        Task { @MainActor in
            Self.markPaid(key: key, in: PersistenceController.shared.viewContext)
        }
    }

    /// Anahtar "x-coredata://…/LedgerItem/p12|24321" biçiminde: kalemin adresi ve ay.
    @MainActor
    static func markPaid(key: String, in context: NSManagedObjectContext) {
        let parts = key.split(separator: "|")
        guard parts.count == 2, let url = URL(string: String(parts[0])), let monthKey = Int32(parts[1]),
              let coordinator = context.persistentStoreCoordinator,
              // Geçersiz adres Core Data'da istisna fırlatır; önce bizim depolarımızdan birine ait olduğunu doğrula.
              url.scheme == "x-coredata", url.pathComponents.count >= 3,
              coordinator.persistentStores.contains(where: { $0.identifier == url.host }),
              let id = coordinator.managedObjectID(forURIRepresentation: url),
              let item = try? context.existingObject(with: id) as? LedgerItem else { return }
        let rates = RateService().table
        guard let line = Ledger.line(for: item, month: Month(key: monthKey), rates: rates),
              line.status == .pending else { return }
        context.setStatus(.paid, for: line, rates: rates)
    }
}
#endif
