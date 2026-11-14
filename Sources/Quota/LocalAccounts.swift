import Foundation

struct LocalAccount: Codable, Identifiable, Sendable {
    var id: UUID
    var provider: T3Provider
    var name: String
}
struct AccountDocument: Codable {
    var accounts: [LocalAccount] = []
    var hidden: Set<String> = []
}

/// Stores names and isolated CLI homes only. The official CLIs own their credentials.
struct LocalAccounts: Sendable {
    var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Allot")
    private var file: URL { directory.appendingPathComponent("accounts.json") }
    func load() throws -> AccountDocument {
        guard FileManager.default.fileExists(atPath: file.path) else { return AccountDocument() }
        let document = try JSONDecoder().decode(AccountDocument.self, from: Data(contentsOf: file))
        guard Set(document.accounts.map(\.id)).count == document.accounts.count,
              document.accounts.allSatisfy({ [.codex, .claude].contains($0.provider) && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 }) else { throw UsageFailure("Account settings are invalid.") }
        return document
    }
    func save(_ document: AccountDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(document).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func account(_ local: LocalAccount) -> T3Account {
        let home = directory.appendingPathComponent("Accounts/\(local.id.uuidString)").path
        let variable = local.provider == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
        return T3Account(id: "allot-" + local.id.uuidString, provider: local.provider, name: local.name, home: home,
            environment: [variable: home, "ANTHROPIC_API_KEY": "", "ANTHROPIC_AUTH_TOKEN": "", "CLAUDE_CODE_OAUTH_TOKEN": "", "OPENAI_API_KEY": "", "CODEX_API_KEY": ""])
    }
    func add(provider: T3Provider, name: String) throws -> T3Account {
        guard [.codex, .claude].contains(provider), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw UsageFailure(L.text("Enter an account name.")) }
        var document = try load()
        let local = LocalAccount(id: UUID(), provider: provider, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        let account = account(local)
        try FileManager.default.createDirectory(atPath: account.home!, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if provider == .codex {
            let config = URL(fileURLWithPath: account.home!).appendingPathComponent("config.toml")
            try Data("cli_auth_credentials_store = \"keyring\"\n".utf8).write(to: config, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        }
        document.accounts.append(local)
        try save(document)
        return account
    }
    func remove(_ account: T3Account) throws {
        var document = try load()
        document.accounts.removeAll { "allot-" + $0.id.uuidString == account.id }
        document.hidden.insert(account.id)
        try save(document)
    }
    func restoreDiscovered() throws {
        var document = try load(); document.hidden = []; try save(document)
    }
    static func signIn(_ account: T3Account) async throws {
        if account.provider == .cursor, let database = account.configuration["localDatabase"] {
            _ = try await CursorCredentials.token(database: database, allowInteraction: true)
            return
        }
        let command = account.provider == .claude ? "claude" : "codex"
        guard let executable = Command.executable(command) else { throw UsageFailure(L.text("Install the provider CLI first.")) }
        _ = try await Command.run(executable, account.provider == .claude ? ["auth", "login", "--claudeai"] : ["login"], environment: account.environment, timeout: 180)
    }
}
