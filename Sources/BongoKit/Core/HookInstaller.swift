import Foundation

/// Registers (and removes) our hooks in `~/.claude/settings.json`.
///
/// This file usually already belongs to the user — other hooks, permissions, model
/// choice. So every operation here is a **merge keyed on our own command path**:
/// we rewrite entries we recognise as ours and leave every other entry untouched.
/// A backup is taken before any write, because getting this wrong breaks the
/// user's Claude Code, not just the cats.
enum HookInstaller {

    /// Events we ask Claude Code for. `MessageDisplay` is the one that matters for
    /// the rhythm — it carries the assistant text the drumming length is derived
    /// from. The rest set state.
    static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "MessageDisplay", "Stop", "StopFailure",
        "SubagentStart", "SubagentStop", "Notification",
    ]

    static var settingsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    enum InstallError: LocalizedError {
        case unreadableSettings
        case unexpectedShape(String)

        var errorDescription: String? {
            switch self {
            case .unreadableSettings:
                return "~/.claude/settings.json exists but is not valid JSON. Fix it before installing."
            case .unexpectedShape(let key):
                return "~/.claude/settings.json has an unexpected shape at '\(key)'. Not touching it."
            }
        }
    }

    static var isInstalled: Bool {
        guard let settings = try? loadSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.contains { event in
            (hooks[event] as? [[String: Any]])?.contains(where: isOurs) == true
        }
    }

    static func install() throws {
        try writeScript()
        var settings = try loadSettings()
        var hooks = try hooksSection(of: settings)

        for event in events {
            var groups = try groupList(hooks[event], event: event)
            groups.removeAll(where: isOurs)
            groups.append(ourGroup())
            hooks[event] = groups
        }

        settings["hooks"] = hooks
        try save(settings)
        AppLog.write("installed hooks for \(events.count) events")
    }

    static func uninstall() throws {
        var settings = try loadSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for event in events {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll(where: isOurs)
            // Drop the key entirely when we were its only user, so uninstalling
            // leaves no empty scaffolding behind.
            if groups.isEmpty { hooks[event] = nil } else { hooks[event] = groups }
        }

        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try save(settings)
        try? FileManager.default.removeItem(at: HookTransport.hookScript)
        AppLog.write("uninstalled hooks")
    }

    // MARK: - Settings I/O

    private static func loadSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile), !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let settings = object as? [String: Any] else { throw InstallError.unreadableSettings }
        return settings
    }

    private static func hooksSection(of settings: [String: Any]) throws -> [String: Any] {
        guard let existing = settings["hooks"] else { return [:] }
        guard let hooks = existing as? [String: Any] else { throw InstallError.unexpectedShape("hooks") }
        return hooks
    }

    private static func groupList(_ value: Any?, event: String) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let groups = value as? [[String: Any]] else { throw InstallError.unexpectedShape("hooks.\(event)") }
        return groups
    }

    private static func save(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        // Prove it round-trips before replacing a file Claude Code depends on.
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw InstallError.unexpectedShape("serialised output")
        }
        try backupExistingSettings()
        try data.write(to: settingsFile, options: .atomic)
    }

    private static func backupExistingSettings() throws {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = HookTransport.supportDirectory.appendingPathComponent("settings-backup-\(stamp).json")
        try? FileManager.default.copyItem(at: settingsFile, to: backup)
    }

    // MARK: - Our entries

    /// Recognises our own hook group by the script it points at. Matching on the
    /// path (not on an index or a name) is what lets install run repeatedly without
    /// stacking duplicates and lets uninstall spare everyone else's hooks.
    private static func isOurs(_ group: [String: Any]) -> Bool {
        guard let entries = group["hooks"] as? [[String: Any]] else { return false }
        return entries.contains { ($0["command"] as? String) == HookTransport.hookScript.path }
    }

    private static func ourGroup() -> [String: Any] {
        [
            "matcher": "",
            "hooks": [[
                "type": "command",
                "command": HookTransport.hookScript.path,
                "timeout": 5,
            ]],
        ]
    }

    // MARK: - Hook script

    /// The hook is a three-line shell script instead of a real binary so it starts
    /// in ~1ms and needs no runtime installed. It always exits 0: a hook that fails
    /// loudly would interrupt the user's actual work over a desktop toy.
    private static func writeScript() throws {
        let script = """
        #!/bin/sh
        # BongoTokenBar hook — forwards the Claude Code hook payload to the running app.
        # Never fails, never blocks: the app is optional, the user's session is not.
        RUNTIME="$HOME/.bongotokenbar/runtime.json"
        [ -f "$RUNTIME" ] || exit 0
        PORT=$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\\([0-9]*\\).*/\\1/p' "$RUNTIME")
        TOKEN=$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\\([a-f0-9]*\\)".*/\\1/p' "$RUNTIME")
        [ -n "$PORT" ] && [ -n "$TOKEN" ] || exit 0
        /usr/bin/curl -s -m 0.25 -X POST \\
          -H 'Content-Type: application/json' \\
          -H "x-bongo-token: $TOKEN" \\
          --data-binary @- "http://127.0.0.1:$PORT/event" >/dev/null 2>&1
        exit 0
        """
        try script.write(to: HookTransport.hookScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: HookTransport.hookScript.path)
    }
}
