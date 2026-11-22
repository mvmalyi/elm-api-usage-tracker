import Foundation
import Security

public enum APIKeySource: String, Sendable, Equatable {
    case keychain
    case environment
    case none
}

public struct ResolvedAPIKey: Sendable, Equatable {
    public let value: String?
    public let source: APIKeySource

    public init(value: String?, source: APIKeySource) {
        self.value = value
        self.source = source
    }
}

public enum KeychainError: LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error (\(status)): \(message)"
            }
            return "Keychain error (\(status))."
        case .encodingFailed:
            return "Could not encode API key."
        }
    }
}

public struct KeychainStore: Sendable {
    public static let defaultService = "uk.ac.edina.elm-api-usage-tracker"
    public static let defaultAccount = "elm-api-key"
    public static let environmentVariableName = "ELM_API_KEY"

    /// Standard shell startup files directly inside `$HOME` (never touching TCC-protected
    /// folders like `~/Documents`), ordered from lowest to highest precedence.
    public static let shellProfileFilenames = [
        ".profile",
        ".bash_profile",
        ".bashrc",
        ".zshenv",
        ".zprofile",
        ".zshrc"
    ]

    private let service: String
    private let account: String

    public init(
        service: String = KeychainStore.defaultService,
        account: String = KeychainStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    public func readKeychainKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func readEnvironmentKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let raw = environment[Self.environmentVariableName] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Reads a static `ELM_API_KEY=...` / `export ELM_API_KEY=...` assignment directly from
    /// shell dotfiles in `$HOME` without spawning a shell subprocess (avoiding TCC folder prompts).
    public func readShellProfileKey(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        var resolved: String?
        for filename in Self.shellProfileFilenames {
            let fileURL = homeDirectory.appendingPathComponent(filename)
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            if let value = Self.parseShellAssignment(in: contents, variableName: Self.environmentVariableName) {
                resolved = value
            }
        }
        return resolved
    }

    public func resolveKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = FileManager.default.homeDirectoryForCurrentUser
    ) -> ResolvedAPIKey {
        if let keychainKey = readKeychainKey() {
            return ResolvedAPIKey(value: keychainKey, source: .keychain)
        }
        if let envKey = readEnvironmentKey(environment: environment) {
            return ResolvedAPIKey(value: envKey, source: .environment)
        }
        if let homeDirectory, let profileKey = readShellProfileKey(homeDirectory: homeDirectory) {
            return ResolvedAPIKey(value: profileKey, source: .environment)
        }
        return ResolvedAPIKey(value: nil, source: .none)
    }

    /// Parses the last static assignment for `variableName` in shell dotfile text.
    /// Supports `export VAR='...'`, `export VAR="..."`, `VAR=...`, and ignores comments
    /// or dynamic command substitutions (`$(...)`, backticks, variable expansions).
    public static func parseShellAssignment(in contents: String, variableName: String) -> String? {
        var lastValue: String?

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("export") {
                let afterExport = line.dropFirst("export".count)
                guard let first = afterExport.first, first.isWhitespace else {
                    continue
                }
                line = afterExport.trimmingCharacters(in: .whitespaces)
            }

            guard line.hasPrefix(variableName) else {
                continue
            }
            let afterName = line.dropFirst(variableName.count).trimmingCharacters(in: .whitespaces)
            guard afterName.hasPrefix("=") else {
                // e.g. bare `export ELM_API_KEY` without an assignment
                continue
            }

            let rhs = afterName.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let parsed = parseShellValue(rhs), !parsed.isEmpty else {
                continue
            }
            lastValue = parsed
        }

        return lastValue
    }

    private static func parseShellValue(_ raw: String) -> String? {
        guard let first = raw.first else { return nil }

        if first == "'" {
            // Single-quoted literal: everything until the closing single quote is literal.
            let rest = raw.dropFirst()
            guard let closingIndex = rest.firstIndex(of: "'") else { return nil }
            return String(rest[..<closingIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if first == "\"" {
            // Double-quoted string: skip dynamic expansions (`$...` or backticks).
            let rest = raw.dropFirst()
            var result = ""
            var escaped = false
            var closed = false

            for ch in rest {
                if escaped {
                    result.append(ch)
                    escaped = false
                    continue
                }
                if ch == "\\" {
                    escaped = true
                    continue
                }
                if ch == "\"" {
                    closed = true
                    break
                }
                if ch == "$" || ch == "`" {
                    return nil
                }
                result.append(ch)
            }
            guard closed else { return nil }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Unquoted value: stop at inline `#` comment or whitespace, reject dynamic expressions.
        var token = raw
        if let commentIndex = token.firstIndex(of: "#") {
            token = String(token[..<commentIndex])
        }
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.contains("$") || token.contains("`") {
            return nil
        }
        return token.isEmpty ? nil : token
    }

    public func saveKey(_ rawKey: String) throws {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteKey()
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrLabel as String] = "ELM API Key"
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }

        throw KeychainError.unexpectedStatus(updateStatus)
    }

    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
