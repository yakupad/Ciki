import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Saatteki veri: iPhone'un gönderdiği özet. Saat kendi App Group'una da yazar, komplikasyonlar oradan okur.
@Observable
final class WatchStore {
    private(set) var snapshot: WidgetSnapshot?
    /// Saatte "ödendi" işaretlenip iPhone'un onayı beklenen ödemeler.
    private(set) var pendingPaid: Set<String> = []

    private let connection = WatchConnection()

    init() {
        snapshot = WidgetSnapshot.load()
        #if DEBUG
        // "-sampleSnapshot": iPhone bağlantısı olmadan ekranları görmek için örnek özet.
        if CommandLine.arguments.contains("-sampleSnapshot") {
            snapshot = .placeholder
        }
        #endif
        connection.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        connection.activate()
    }

    /// Saatte gezinilebilen aylar (geçmiş 3, gelecek 6).
    var months: [WidgetSnapshot.MonthSummary] { snapshot?.monthList ?? [] }

    /// Bir ayın bekleyen ödemeleri; saatte "ödendi" denenler onay gelene kadar gizlenir.
    func payments(in month: WidgetSnapshot.MonthSummary) -> [WidgetSnapshot.Payment] {
        month.payments.filter { !pendingPaid.contains($0.id) }
    }

    /// iPhone yakındaysa hemen, değilse kuyruğa alınarak gönderilir. Liste hemen güncellenir.
    func markPaid(_ payment: WidgetSnapshot.Payment) {
        guard let key = payment.key else { return }
        pendingPaid.insert(payment.id)
        connection.sendMarkPaid(key)
    }

    private func apply(_ new: WidgetSnapshot) {
        snapshot = new
        // iPhone'dan gelen yeni özette artık olmayan ödemeler onaylanmış demektir.
        let remaining = Set(new.monthList.flatMap(\.payments).map(\.id))
        pendingPaid = pendingPaid.intersection(remaining)
        new.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// WCSession temsilcisi; metotlar arka plan kuyruğunda çağrılır, sonuç ana aktöre aktarılır.
nonisolated final class WatchConnection: NSObject, WCSessionDelegate, @unchecked Sendable {
    @MainActor var onSnapshot: ((WidgetSnapshot) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendMarkPaid(_ key: String) {
        let session = WCSession.default
        let payload: [String: Any] = ["markPaid": key]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // Anlık gönderim başarısız olursa kuyruğa al.
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        deliver(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    private func deliver(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data, let snapshot = WidgetSnapshot.decode(data) else { return }
        Task { @MainActor in self.onSnapshot?(snapshot) }
    }
}
