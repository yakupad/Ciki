import SwiftUI

/// Verilerin nerede tutulduğunu ve nereye gittiğini sade bir dille anlatır.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                PrivacyRow(symbol: "iphone", title: "Cihazınızda",
                           text: "Kalemler, kayıtlar, kişiler ve IBAN'lar bu cihazdaki veritabanında durur. iOS cihaz şifrelemesiyle korunur.")
                PrivacyRow(symbol: "icloud", title: "Kendi iCloud hesabınızda",
                           text: "iCloud açıksa aynı veriler sizin özel iCloud alanınıza eşitlenir. Haneyi paylaşırsanız yalnızca davet ettiğiniz kişilerle paylaşılır. Uygulamanın geliştiricisi bu verilere erişemez.")
                PrivacyRow(symbol: "network", title: "İnternete giden tek istek",
                           text: "Döviz kurları için TCMB'nin herkese açık kur dosyası indirilir (tcmb.gov.tr). Bu istekte sizinle ilgili hiçbir bilgi gönderilmez.")
                PrivacyRow(symbol: "hand.raised.fill", title: "Toplanmayanlar",
                           text: "Reklam, analiz, takip, konum ya da rehber erişimi yok. Uygulama kullanımınız ölçülmez.")
            }
            Section {
                PrivacyRow(symbol: "gearshape", title: "Bu telefona özel ayarlar",
                           text: "Görünüm, gösterim para birimi, kilit, hatırlatmalar ve \"bu telefonu kullanan\" seçimi yalnızca bu telefonda saklanır, eşitlenmez.")
                PrivacyRow(symbol: "lock.fill", title: "Ekstra koruma",
                           text: "Face ID kilidi açıkken uygulama değiştiricide ve widget'ta tutarlar görünmez. Bildirimlerde tutarı gizlemek için Hatırlatmalar bölümünü kullanın.")
            }
        }
        .navigationTitle("Verileriniz nerede?")
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.petrol)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Color.ikincil)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
