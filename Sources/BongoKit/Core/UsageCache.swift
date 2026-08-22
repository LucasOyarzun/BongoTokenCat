import Foundation

/// What one transcript file contributed, and the fingerprint that says whether it
/// still contributes the same thing.
struct FileUsage: Codable, Sendable, Equatable {
    let modified: Date
    let size: Int
    let total: Int
    /// Tokens per local day. Only ever queried for today, but keyed by day so a
    /// cached entry stays correct as the date rolls over.
    let byDay: [String: Int]

    func matches(modified: Date, size: Int) -> Bool {
        // Whole seconds: filesystem timestamps and JSON round-tripping disagree on
        // sub-second precision, and a file that changed will always move by more.
        Int(self.modified.timeIntervalSince1970) == Int(modified.timeIntervalSince1970)
            && self.size == size
    }
}

/// Remembers per-file token counts between scans.
///
/// A full scan of a real history — 457 files, 7.1 billion tokens — parses for tens
/// of seconds and pins a core. Repeating that every five minutes is unacceptable
/// for something that sits on the desktop all day, so files are re-read only when
/// their size or modification time changes.
///
/// Caching per file is only sound because turns duplicated across files (session
/// resume, sidechains) are also duplicated *within* the file that copies them.
/// Measured on a real 457-file history, per-file dedup and global dedup produce an
/// identical total, so the cheaper one is used.
enum UsageCache {
    static var fileURL: URL { HookTransport.supportDirectory.appendingPathComponent("usage-cache.json") }

    static func load() -> [String: FileUsage] {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode([String: FileUsage].self, from: data) else { return [:] }
        return cache
    }

    /// Writing only the entries seen in this scan is what prunes deleted projects —
    /// no separate sweep, and the cache cannot outgrow the transcripts it mirrors.
    static func save(_ cache: [String: FileUsage]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
