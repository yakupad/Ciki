import CloudKit
import CoreData
import UIKit

/// iCloud davetlerini kabul etmek için sahne temsilcisi. SwiftUI yaşam döngüsünde
/// `windowScene(_:userDidAcceptCloudKitShareWith:)` yalnızca sahne temsilcisine gelir.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Saatten gelen "ödendi" işareti uygulamayı arka planda uyandırabilir; oturum en başta kurulur.
        #if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
        WatchSync.shared.activate()
        #endif
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Uygulama kapalıyken davet bağlantısıyla açılırsa.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await CloudSharing.accept(metadata) }
        }
        #if DEBUG && targetEnvironment(macCatalyst)
        // Mağaza görselleri için pencereyi sabit boyutta aç: -macWindowSize 1280x800
        if let value = UserDefaults.standard.string(forKey: "macWindowSize"),
           let windowScene = scene as? UIWindowScene {
            let parts = value.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                let size = CGSize(width: parts[0], height: parts[1])
                windowScene.sizeRestrictions?.minimumSize = size
                windowScene.sizeRestrictions?.maximumSize = size
            }
        }
        #endif
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await CloudSharing.accept(metadata) }
    }
}

/// Haneyi başkalarıyla paylaşma, daveti kabul etme ve paylaşım durumunu okuma.
enum CloudSharing {
    /// Davet kabul edildikten sonra uygulamanın kullanıcıya soracağı durum.
    static let didAcceptShare = Notification.Name("CloudSharing.didAcceptShare")

    static var persistence: PersistenceController { .shared }

    static func accept(_ metadata: CKShare.Metadata) async {
        guard let store = persistence.sharedStore else { return }
        do {
            try await persistence.container.acceptShareInvitations(from: [metadata], into: store)
            NotificationCenter.default.post(name: didAcceptShare, object: nil)
        } catch {
            print("Davet kabul edilemedi: \(error)")
        }
    }

    static func share(for household: Household) -> CKShare? {
        guard PersistenceController.isCloudKitAvailable else { return nil }
        return try? persistence.container.fetchShares(matching: [household.objectID])[household.objectID]
    }

    /// Haneyi ve ona bağlı kişileri, kalemleri, kayıtları ve hesapları paylaşır.
    static func createShare(for household: Household) async throws -> CKShare {
        let (_, share, _) = try await persistence.container.share([household], to: nil)
        share[CKShare.SystemFieldKey.title] = household.name ?? String(localized: "Çıkı")
        return share
    }

    static func accountStatus() async -> CKAccountStatus {
        guard PersistenceController.isCloudKitAvailable else { return .noAccount }
        return (try? await persistence.cloudContainer.accountStatus()) ?? .couldNotDetermine
    }

    /// iOS'un paylaşım ekranını (davet gönderme, katılımcılar, paylaşımı durdurma) en üstteki ekrandan açar.
    static func presentSharingController(for share: CKShare) {
        let controller = UICloudSharingController(share: share, container: persistence.cloudContainer)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = SharingDelegate.shared
        controller.modalPresentationStyle = .formSheet
        topViewController()?.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = SharingDelegate()

    func itemTitle(for csc: UICloudSharingController) -> String? {
        csc.share?[CKShare.SystemFieldKey.title] as? String ?? String(localized: "Çıkı")
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Paylaşım kaydedilemedi: \(error)")
    }
}

extension CKShare.Participant {
    var displayName: String {
        if let components = userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        return userIdentity.lookupInfo?.emailAddress ?? userIdentity.lookupInfo?.phoneNumber ?? String(localized: "Davetli")
    }
}
