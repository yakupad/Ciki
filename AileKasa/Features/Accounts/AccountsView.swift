import SwiftUI
import CoreData
import UIKit

/// Ailenin kendi hesapları ve ödeme yapılan kişi/kurumların IBAN rehberi.
struct AccountsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [SortDescriptor(\Person.sortOrder)])
    private var people: FetchedResults<Person>

    @State private var query = ""
    @State private var editing: AccountRoute?
    @State private var copiedID: NSManagedObjectID?
    @State private var accountToDelete: Account?

    enum AccountRoute: Identifiable {
        case new
        case edit(Account)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let account): account.objectID.uriRepresentation().absoluteString
            }
        }
    }

    var body: some View {
        let visible = accounts.filter(matches)

        List {
            if accounts.isEmpty {
                ContentUnavailableView {
                    Label("Henüz hesap yok", systemImage: "building.columns")
                } description: {
                    Text("Kendi hesaplarınızı ve ödeme yaptığınız kişi ve kurumların IBAN'larını burada saklayın. Bir hesaba dokununca IBAN kopyalanır.")
                } actions: {
                    Button("Hesap ekle") { editing = .new }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }

            ForEach(people, id: \.objectID) { person in
                section(Text(verbatim: person.displayName),
                        visible.filter { $0.isOwn && $0.owner == person })
            }
            section(Text("Ortak hesaplar"), visible.filter { $0.isOwn && $0.owner == nil })
            section(Text("Ödeme yapılanlar"), visible.filter { !$0.isOwn })
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.zemin)
        .navigationTitle("Hesaplar")
        .searchable(text: $query, prompt: Text("Ad, banka ya da IBAN ara"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Yeni hesap", systemImage: "plus") { editing = .new }
                    .labelStyle(.titleAndIcon)
            }
        }
        .sheet(item: $editing) { route in
            switch route {
            case .new: AccountEditorView(account: nil)
            case .edit(let account): AccountEditorView(account: account)
            }
        }
        .confirmationDialog("Hesap silinsin mi?", isPresented: Binding(
            get: { accountToDelete != nil },
            set: { if !$0 { accountToDelete = nil } }
        ), titleVisibility: .visible, presenting: accountToDelete) { account in
            Button("Sil", role: .destructive) {
                context.delete(account)
                context.saveIfNeeded()
            }
        } message: { account in
            Text("\(account.displayTitle) rehberden silinir. Bağlı kalemler silinmez.")
        }
        .sensoryFeedback(.success, trigger: copiedID)
    }

    @ViewBuilder
    private func section(_ header: Text, _ accounts: [Account]) -> some View {
        if !accounts.isEmpty {
            Section {
                ForEach(accounts, id: \.objectID) { account in
                    AccountRow(account: account, isCopied: copiedID == account.objectID)
                        .contentShape(Rectangle())
                        .onTapGesture { copyIBAN(account) }
                        .swipeActions(edge: .trailing) {
                            Button("Sil", systemImage: "trash", role: .destructive) { accountToDelete = account }
                            Button("Düzenle", systemImage: "pencil") { editing = .edit(account) }
                                .tint(.petrol)
                        }
                        .contextMenu {
                            Button("IBAN'ı kopyala", systemImage: "doc.on.doc") { copyIBAN(account) }
                            if let holder = account.holderName, !holder.isEmpty {
                                Button("Alıcı adını kopyala", systemImage: "person.text.rectangle") {
                                    UIPasteboard.general.string = holder
                                }
                            }
                            ShareLink(item: account.shareText) {
                                Label("Paylaş", systemImage: "square.and.arrow.up")
                            }
                            Button("Düzenle", systemImage: "pencil") { editing = .edit(account) }
                            Button("Sil", systemImage: "trash", role: .destructive) { accountToDelete = account }
                        }
                }
            } header: {
                header
            }
        }
    }

    private func matches(_ account: Account) -> Bool {
        guard !query.isEmpty else { return true }
        let compactQuery = IBAN.normalized(query)
        return [account.title, account.holderName, account.bankName, account.note]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
            || (!compactQuery.isEmpty && IBAN.normalized(account.iban ?? "").contains(compactQuery))
    }

    private func copyIBAN(_ account: Account) {
        let iban = IBAN.normalized(account.iban ?? "")
        guard !iban.isEmpty else {
            editing = .edit(account)
            return
        }
        UIPasteboard.general.string = iban
        withAnimation { copiedID = account.objectID }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { if copiedID == account.objectID { copiedID = nil } }
        }
    }
}

struct AccountRow: View {
    let account: Account
    var isCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BankBadge(bank: account.bankName, symbol: account.isOwn ? "person.fill" : "building.2.fill")
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(account.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if isCopied {
                        Label("Kopyalandı", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.gelir)
                            .transition(.opacity)
                    } else if account.currency != .tl {
                        Text(verbatim: account.currency.title)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let iban = account.iban, !iban.isEmpty {
                    Text(verbatim: account.formattedIBAN)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(IBAN.validate(iban) == .valid ? Color.primary : Color.gider)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("IBAN'ı kopyalamak için dokunun")
    }

    private var subtitle: String? {
        let parts = [account.holderName, account.bankName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != account.displayTitle }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Banka baş harfli rozet; banka yoksa simge.
struct BankBadge: View {
    let bank: String?
    var symbol = "building.columns.fill"
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(bank.map { Color(hex: Banks.colorHex(for: $0)) } ?? Color.petrol)
            if let bank {
                Text(verbatim: Banks.initials(for: bank))
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Kayıt ekranında kalemin ödeme hesabı: alıcı, banka ve kopyalanabilir IBAN.
struct PayeeCard: View {
    let account: Account
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AccountRow(account: account, isCopied: copied)
            Button(copied ? "Kopyalandı" : "IBAN'ı kopyala", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = IBAN.normalized(account.iban ?? "")
                withAnimation { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { copied = false }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled((account.iban ?? "").isEmpty)
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }
}

#Preview {
    NavigationStack { AccountsView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
