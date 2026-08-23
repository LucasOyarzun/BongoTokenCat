import Foundation
import Security

/// The OAuth token Claude Code already holds, borrowed to ask the usage endpoint
/// about *this* machine's limits.
///
/// Nothing here is ever bundled into the app: the token is read at runtime from the
/// account signed in on the machine that is running, so every install reports its
/// own numbers and no credential travels with the binary.
struct ClaudeCredential: Sendable {
    let accessToken: String
    let expiresAt: Date?
    let source: Source

    /// Carried so a rejected token can be blamed on the place it came from. A file
    /// token can be well within its stated lifetime and still be dead — signing in
    /// elsewhere revokes it server-side without rewriting the file — and without
    /// knowing which source produced it, the app would keep replaying the same dead
    /// token every couple of minutes and never reach the live one in the Keychain.
    enum Source: Sendable, Equatable { case file, keychain }

    /// A minute of slack, because a token that expires mid-flight fails the request
    /// it was fetched for and the retry costs more than fetching a fresh one.
    var isUsable: Bool {
        guard let expiresAt else { return true }
        return expiresAt > Date().addingTimeInterval(60)
    }
}

enum CredentialError: LocalizedError, Equatable {
    case notFound
    case loggedOut
    case needsAuthorization
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Claude Code credential on this Mac."
        case .loggedOut:
            return "Claude Code is signed out. Run `claude auth login` and try again."
        case .needsAuthorization:
            return "BongoTokenCat needs your permission to read the Claude Code credential."
        case .keychain(let status):
            return "Could not read the Keychain (status \(status))."
        }
    }
}

/// The two places Claude Code keeps its token. Which one to try, and in what order,
/// is a policy question that belongs to the caller — see `AppModel.refreshLimits`.
/// This type only knows how to read them.
enum ClaudeCredentials {
    static let keychainService = "Claude Code-credentials"

    // MARK: - File

    /// Free of side effects and free of dialogs, which is what makes it the one an
    /// unattended refresh may use.
    nonisolated static func fromFile() -> ClaudeCredential? {
        guard let data = try? Data(contentsOf: credentialsFile) else { return nil }
        return parse(data, source: .file)
    }

    /// Mirrors how Claude Code itself relocates: `CLAUDE_CONFIG_DIR` may name several
    /// directories, and the first is the one in use.
    static var credentialsFile: URL {
        let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .split(separator: ",")
            .map { NSString(string: $0.trimmingCharacters(in: .whitespaces)).expandingTildeInPath }
            .first { !$0.isEmpty }
        let directory = configured.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return directory.appendingPathComponent(".credentials.json")
    }

    // MARK: - Keychain

    /// A blocking call macOS may stall on for seconds when the login keychain is
    /// locked or the app has not been approved, so it is never made from the main
    /// actor. `allowPrompt` separates "the user just clicked something" from "a timer
    /// fired": only the former may put a dialog on screen.
    nonisolated static func fromKeychain(allowPrompt: Bool) throws -> ClaudeCredential {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowPrompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            break
        // All three mean the same thing to the user — nobody has said yes yet — and
        // the same card answers all three. Only the first arrives without a dialog.
        case errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed:
            throw CredentialError.needsAuthorization
        case errSecItemNotFound:
            throw CredentialError.notFound
        default:
            throw CredentialError.keychain(status)
        }

        guard let data = item as? Data else { throw CredentialError.notFound }
        guard let credential = parse(data, source: .keychain) else {
            // Valid JSON with no account section means signed out, which is a
            // different instruction to the user than a corrupt item.
            throw hasAccountSection(data) ? CredentialError.notFound : CredentialError.loggedOut
        }
        return credential
    }

    // MARK: - Parsing

    /// Pure so the shapes can be tested without a Keychain or a signed-in account.
    static func parse(_ data: Data, source: ClaudeCredential.Source) -> ClaudeCredential? {
        guard let oauth = accountSection(data),
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return ClaudeCredential(accessToken: token,
                                expiresAt: expiry(from: oauth["expiresAt"]),
                                source: source)
    }

    static func hasAccountSection(_ data: Data) -> Bool { accountSection(data) != nil }

    /// Cast rather than compare against nil: a signed-out Claude Code writes an
    /// explicit JSON `null` here, which decodes to `NSNull` and would read as
    /// "present" to a nil check.
    private static func accountSection(_ data: Data) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["claudeAiOauth"] as? [String: Any]
    }

    /// Written as seconds or milliseconds depending on the Claude Code version, and
    /// sometimes as a string. Ten billion is the discriminator — as seconds it is
    /// the year 2286, as milliseconds it is 1970.
    private static func expiry(from raw: Any?) -> Date? {
        let seconds: Double? = switch raw {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as String: Double(value)
        default: nil
        }
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
    }
}
