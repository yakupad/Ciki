import SwiftUI
import CloudKit
import CoreData

/// Ayarlar'daki iCloud bölümü: haneyi eşle paylaşma ve katılımcılar.
struct SharingSection: View {
    @Environment(\.managedObjectContext) private var context

    @State private var status: CKAccountStatus?
    @State private var share: CKShare?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            content
        } header: {
            Text("iCloud ile ortak kullanım")
        } footer: {
            footer
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case nil:
            HStack {
                ProgressView()
                Text("iCloud durumu kontrol ediliyor…").foregroundStyle(.secondary)
            }
        case .available?:
            if let share {
                ForEach(share.participants, id: \.self) { participant in
                    ParticipantRow(participant: participant, isMe: participant == share.currentUserParticipant)
                }
                Button("Paylaşımı yönet", systemImage: "person.2.badge.gearshape") {
                    CloudSharing.presentSharingController(for: share)
                }
            } else {
                Button {
                    Task { await startSharing() }
                } label: {
                    HStack {
                        Label("Eşinizle paylaşın", systemImage: "person.2.fill")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isWorking)
            }
        case .some:
            Label("Bu cihazda iCloud'a giriş yapılmamış. Veriler yalnızca bu cihazda.", systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let errorMessage {
            Text(errorMessage).foregroundStyle(Color.gider)
        } else if let share, share.currentUserParticipant?.role != .owner {
            Text("Bu hane size paylaşıldı. Eklediğiniz ve değiştirdiğiniz her şey diğer kişide de görünür.")
        } else if share != nil {
            Text("Davet kabul edildikten sonra iki telefon aynı kalemleri, kayıtları ve hesapları görür ve düzenler. Gösterim para birimi, kilit ve hatırlatmalar her cihazda ayrı ayarlanır.")
        } else {
            Text("Hanenizi paylaştığınızda eşinize Mesajlar, WhatsApp ya da e-posta ile bir davet gönderilir. Eşiniz daveti açınca tüm kayıtlar onun telefonuna da gelir.")
        }
    }

    private func reload() async {
        status = await CloudSharing.accountStatus()
        share = CloudSharing.share(for: context.currentHousehold())
    }

    private func startSharing() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let created = try await CloudSharing.createShare(for: context.currentHousehold())
            share = created
            errorMessage = nil
            CloudSharing.presentSharingController(for: created)
        } catch {
            errorMessage = String(localized: "Paylaşım başlatılamadı. İnternet bağlantınızı ve iCloud hesabınızı kontrol edip yeniden deneyin.")
            print("Paylaşım oluşturulamadı: \(error)")
        }
    }
}

private struct ParticipantRow: View {
    let participant: CKShare.Participant
    let isMe: Bool

    var body: some View {
        HStack {
            Image(systemName: participant.role == .owner ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                .foregroundStyle(Color.petrol)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: participant.displayName + (isMe ? " " + String(localized: "(siz)") : ""))
                Text(roleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var roleText: String {
        if participant.role == .owner { return String(localized: "Haneyi paylaşan") }
        switch participant.acceptanceStatus {
        case .accepted: return String(localized: "Katıldı")
        case .pending: return String(localized: "Davet bekliyor")
        case .removed: return String(localized: "Çıkarıldı")
        default: return String(localized: "Bilinmiyor")
        }
    }
}
