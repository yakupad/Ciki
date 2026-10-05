import SwiftUI
import LocalAuthentication
import UIKit

/// Face ID / Touch ID / cihaz parolası ile uygulama kilidi.
/// Kilit açıkken uygulama arka plana geçince kilitlenir; uygulama değiştiricide tutarlar gizlenir.
@Observable
final class AppLock {
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    var errorMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: "lock.enabled")
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    /// Cihazda kullanılabilen doğrulama yönteminin adı.
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Cihaz parolası")
        }
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard await authenticate(reason: String(localized: "Kilidi açmak için kimliğinizi doğrulayın")) else { return }
            isEnabled = true
        } else {
            isEnabled = false
            isLocked = false
        }
        defaults.set(isEnabled, forKey: "lock.enabled")
    }

    func lock() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: String(localized: "Aile Kasası'nı açmak için kimliğinizi doğrulayın")) {
            isLocked = false
        }
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = String(localized: "Bu cihazda parola ya da Face ID ayarlı değil. Önce iOS Ayarlar'dan bir parola belirleyin.")
            return false
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            errorMessage = nil
            return success
        } catch {
            return false
        }
    }
}

/// Kilit ekranını, açık sayfaların (sheet) da üstünde ayrı bir pencerede gösterir.
final class LockWindow {
    private var window: UIWindow?

    func update(visible: Bool, lock: AppLock) {
        if visible {
            show(lock: lock)
        } else {
            hide()
        }
    }

    private func show(lock: AppLock) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: LockScreen(lock: lock))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    private func hide() {
        guard let window else { return }
        window.isHidden = true
        self.window = nil
    }
}

struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Color.zemin.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.petrol)
                Text("Aile Kasası kilitli")
                    .font(.title2.weight(.bold))
                if lock.isLocked {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Kilidi aç", systemImage: "faceid")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.petrol)
                    .disabled(lock.isAuthenticating)
                }
                if let error = lock.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}
