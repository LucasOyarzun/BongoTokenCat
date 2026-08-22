import Foundation

/// What an agent is working on, as far as its working directory can tell us.
struct WorkspaceInfo: Sendable, Equatable {
    let directory: String       // the folder name — always available
    let project: String?        // repository name
    let branch: String?         // current git branch

    /// Short label for under a cat. Branches are often prefixed (`lucas/fix-thing`)
    /// and there is no room for the prefix at 200pt wide, so only the last segment
    /// is shown — that is the part that identifies the work.
    var shortLabel: String {
        guard let branch, !branch.isEmpty else { return directory }
        return branch.split(separator: "/").last.map(String.init) ?? branch
    }

    /// Full description for the menu, where there is room for it.
    var fullLabel: String {
        switch (project, branch) {
        case let (project?, branch?): return "\(project) · \(branch)"
        case let (project?, nil):     return "\(project) · \(directory)"
        case let (nil, branch?):      return branch
        case (nil, nil):              return directory
        }
    }
}

/// Resolves the git branch and repository for a working directory.
///
/// Conductor names a workspace folder independently of its branch, and the folder
/// name is what the agent reports. Reading git directly means the label follows the
/// branch even after the folder is renamed, and it works the same for plain
/// checkouts that never went near Conductor.
///
/// This reads `.git` by hand rather than shelling out to `git`: it runs on the hook
/// path, and spawning a process for every tool call across a dozen agents is a cost
/// the animation would feel.
@MainActor
enum GitContext {
    /// Branches change while the app runs, so entries expire. Long enough that a
    /// burst of hook events costs one lookup, short enough that a checkout shows up
    /// while you are still looking at the screen.
    static let cacheLifetime: TimeInterval = 30

    private static var cache: [String: (info: WorkspaceInfo, resolvedAt: Date)] = [:]

    static func info(for path: String, now: Date = Date()) -> WorkspaceInfo {
        if let hit = cache[path], now.timeIntervalSince(hit.resolvedAt) < cacheLifetime {
            return hit.info
        }
        let info = resolve(path)
        cache[path] = (info, now)
        return info
    }

    static func clearCache() { cache.removeAll() }

    // MARK: - Resolution

    static func resolve(_ path: String) -> WorkspaceInfo {
        let directory = URL(fileURLWithPath: path).lastPathComponent
        guard !path.isEmpty, let gitDir = gitDirectory(for: path) else {
            return WorkspaceInfo(directory: directory, project: nil, branch: nil)
        }
        return WorkspaceInfo(directory: directory,
                             project: repositoryName(gitDir: gitDir),
                             branch: branch(gitDir: gitDir))
    }

    /// Finds the `.git` for `path` or any ancestor, following the `gitdir:` pointer
    /// that worktrees use. Conductor workspaces are worktrees, so the pointer case
    /// is the normal one here, not an edge case.
    static func gitDirectory(for path: String) -> URL? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        for _ in 0..<12 {
            let candidate = current.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                guard !isDirectory.boolValue else { return candidate }
                return worktreeGitDir(from: candidate, relativeTo: current)
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return nil
    }

    private static func worktreeGitDir(from pointer: URL, relativeTo base: URL) -> URL? {
        guard let text = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
        let prefix = "gitdir:"
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let raw = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : base.appendingPathComponent(raw).standardizedFileURL
    }

    static func branch(gitDir: URL) -> String? {
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else {
            return nil
        }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        guard trimmed.hasPrefix(refPrefix) else {
            // Detached HEAD holds a raw sha. A short sha is more useful than nothing.
            return trimmed.count >= 7 && !trimmed.contains(" ") ? String(trimmed.prefix(7)) : nil
        }
        return String(trimmed.dropFirst(refPrefix.count))
    }

    /// The repository a worktree belongs to. `commondir` points at the main
    /// repository's `.git`, whose parent is the checkout everyone would name.
    static func repositoryName(gitDir: URL) -> String? {
        let common = commonDirectory(gitDir: gitDir) ?? gitDir
        let root = common.deletingLastPathComponent()   // strip ".git"
        let name = root.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    private static func commonDirectory(gitDir: URL) -> URL? {
        guard let text = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8)
        else { return nil }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : gitDir.appendingPathComponent(raw).standardizedFileURL
    }
}
