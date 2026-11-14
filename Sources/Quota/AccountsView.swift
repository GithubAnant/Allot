import SwiftUI

struct AccountsView: View {
    @Bindable var store: T3Store
    @State private var provider = T3Provider.codex
    @State private var name = ""
    @State private var signingIn = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.text("Accounts")).font(.quota(18, .medium))
            Text(L.text("Each extra account has a separate sign-in. T3 is not required.")).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.accounts) { account in
                        HStack(spacing: 8) {
                            ProviderLogo(provider: account.provider).frame(width: 14, height: 14)
                            Text(account.name).lineLimit(1).help(account.name)
                            Spacer()
                            if [.claude, .codex].contains(account.provider) || account.configuration["localDatabase"] != nil {
                                Button(L.text("Sign in")) { login(account) }.disabled(signingIn)
                            }
                            Button(L.text("Remove")) {
                                do { try store.removeAccount(account) } catch { message = error.localizedDescription }
                            }.disabled(signingIn)
                        }
                    }
                    if store.accounts.isEmpty { Text(L.text("No accounts connected.")).foregroundStyle(Color.muted) }
                }
            }
            Divider()
            HStack {
                Picker(L.text("Provider"), selection: $provider) {
                    Text("Codex").tag(T3Provider.codex)
                    Text("Claude").tag(T3Provider.claude)
                }.labelsHidden().frame(width: 100)
                TextField(L.text("Account name"), text: $name).textFieldStyle(.roundedBorder)
            }
            Button(L.text(signingIn ? "Signing in…" : "Add account")) {
                do {
                    let account = try store.addAccount(provider: provider, name: name)
                    name = ""; login(account)
                } catch { message = error.localizedDescription }
            }.disabled(signingIn || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let message { Text(message).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Link(L.text("Install Codex CLI"), destination: URL(string: "https://developers.openai.com/codex/cli/")!)
                Link(L.text("Install Claude Code"), destination: URL(string: "https://code.claude.com/docs/en/setup")!)
            }
            Button(L.text("Restore discovered accounts")) {
                do { try store.restoreAccounts() } catch { message = error.localizedDescription }
            }.disabled(signingIn)
            Text(L.text("Removing an account stops tracking it. Saved sign-ins and history stay on this Mac.")).font(.quota(9)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 420, height: 500)
            .background(Color.panel).foregroundStyle(Color(white: 0.8)).font(.quota(11)).preferredColorScheme(.dark)
    }
    private func login(_ account: T3Account) {
        signingIn = true; message = L.text("Finish sign-in in your browser, then refresh.")
        Task {
            do { try await LocalAccounts.signIn(account); message = nil }
            catch { message = L.text("Usage unavailable. Check the account sign-in.") + " " + error.localizedDescription }
            signingIn = false
            await store.refresh()
        }
    }
}
