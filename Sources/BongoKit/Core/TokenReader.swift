import Foundation

/// Reads Claude Code's local transcripts and totals the tokens you have spent.
///
/// Only two numbers matter here — today's spend and the lifetime total that drives
/// skin unlocks — so this stays a deliberately small reader rather than a full
/// usage tracker. It parses line by line and only touches lines that mention
/// `usage`, which keeps a 450-file scan well under a second.
enum TokenReader {

    struct Totals: Sendable, Equatable {
        var today = 0
        var lifetime = 0
    }

    /// Every directory Claude Code may keep transcripts in.
    /// One place to add a new root — the scan, the tests and any future cache all
    /// read this same list.
    static var projectRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for path in configured.split(separator: ",") {
                let expanded = NSString(string: path.trimmingCharacters(in: .whitespaces)).expandingTildeInPath
                guard !expanded.isEmpty else { continue }
                roots.insert(URL(fileURLWithPath: expanded).appendingPathComponent("projects"), at: 0)
            }
        }
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func read(roots: [URL] = projectRoots, now: Date = Date()) -> Totals {
        let today = localDay(of: now)
        let recent = utcDaysOverlappingLocalToday(now)
        let cached = UsageCache.load()
        var fresh: [String: FileUsage] = [:]
        var totals = Totals()

        for file in transcriptFiles(in: roots) {
            guard let stamp = fingerprint(of: file) else { continue }
            let usage = cached[file.path].flatMap { $0.matches(modified: stamp.modified, size: stamp.size) ? $0 : nil }
                ?? scan(file, stamp: stamp, recentUTCDays: recent)
            fresh[file.path] = usage
            totals.lifetime += usage.total
            totals.today += usage.byDay[today] ?? 0
        }

        UsageCache.save(fresh)
        return totals
    }

    /// Reads one transcript and totals it. Dedup is per file — see `UsageCache` for
    /// why that is equivalent to deduping across the whole history.
    private static func scan(_ file: URL, stamp: (modified: Date, size: Int),
                             recentUTCDays: Set<String>) -> FileUsage {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else {
            return FileUsage(modified: stamp.modified, size: stamp.size, total: 0, byDay: [:])
        }
        var seen = Set<String>()
        var total = 0
        var byDay: [String: Int] = [:]

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"usage\"") else { continue }
            guard let entry = parse(String(line), recentUTCDays: recentUTCDays) else { continue }
            guard seen.insert(entry.id).inserted else { continue }
            total += entry.tokens
            byDay[entry.day, default: 0] += entry.tokens
        }
        return FileUsage(modified: stamp.modified, size: stamp.size, total: total, byDay: byDay)
    }

    private static func fingerprint(of file: URL) -> (modified: Date, size: Int)? {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate,
              let size = values.fileSize else { return nil }
        return (modified, size)
    }

    /// The UTC calendar days that can contain any instant of the user's local today.
    ///
    /// This is what keeps the scan off ICU. Converting every timestamp to a local
    /// day means building a date formatter per line, and profiling a real 457-file
    /// history showed that alone pinning a core for the whole scan. Only lines
    /// inside this window need the exact conversion; every older line just needs a
    /// day string that provably is not today, and its raw UTC prefix already is one.
    static func utcDaysOverlappingLocalToday(_ now: Date) -> Set<String> {
        let utc = DateFormatter()
        utc.dateFormat = "yyyy-MM-dd"
        utc.timeZone = TimeZone(identifier: "UTC")
        return Set([-86400, 0, 86400].map { utc.string(from: now.addingTimeInterval($0)) })
    }

    // MARK: - Parsing

    struct Entry: Sendable {
        let id: String
        let day: String
        let tokens: Int
    }

    /// `recentUTCDays` is the fast path: a timestamp outside it cannot belong to
    /// local today, so its day is taken straight from the string with no date
    /// parsing at all. Pass an empty set to always convert precisely.
    static func parse(_ line: String, recentUTCDays: Set<String> = []) -> Entry? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }

        let tokens = ["input_tokens", "output_tokens",
                      "cache_creation_input_tokens", "cache_read_input_tokens"]
            .reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
        guard tokens > 0 else { return nil }

        let messageID = message["id"] as? String ?? ""
        let requestID = object["requestId"] as? String ?? ""
        let timestamp = object["timestamp"] as? String ?? ""
        // Fall back to the timestamp when neither id is present: a weaker key still
        // beats counting an entry we cannot distinguish twice.
        let identity = messageID.isEmpty && requestID.isEmpty ? timestamp : "\(messageID)|\(requestID)"
        guard !identity.isEmpty else { return nil }

        let utcDay = String(timestamp.prefix(10))
        let day = recentUTCDays.isEmpty || recentUTCDays.contains(utcDay)
            ? localDay(ofISO: timestamp)
            : utcDay
        return Entry(id: identity, day: day, tokens: tokens)
    }

    // MARK: - Files and dates

    private static func transcriptFiles(in roots: [URL]) -> [URL] {
        let manager = FileManager.default
        return roots.flatMap { root -> [URL] in
            guard let walker = manager.enumerator(at: root,
                                                  includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else { return [] }
            return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        }
    }

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func localDay(of date: Date) -> String { dayFormatter.string(from: date) }

    // Date formatters are documented as safe for concurrent use once configured;
    // building them per call is what made a full scan burn a core.
    nonisolated(unsafe) private static let fractionalParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()
    nonisolated(unsafe) private static let plainParser = ISO8601DateFormatter()

    /// Transcript timestamps are UTC; "today" must mean the user's day, so the
    /// instant is reformatted in local time rather than sliced off the string.
    /// Parsers are hoisted out of the call — building them per line is what made a
    /// full scan burn a core.
    static func localDay(ofISO timestamp: String) -> String {
        let date = fractionalParser.date(from: timestamp) ?? plainParser.date(from: timestamp)
        guard let date else { return "" }
        return dayFormatter.string(from: date)
    }
}

/// Compact token counts for the menu bar: 7.1B, 428.3M, 12.4K.
enum TokenFormatter {
    static func compact(_ value: Int) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K"),
        ]
        let amount = Double(value)
        for unit in units where amount >= unit.threshold {
            return String(format: "%.1f%@", amount / unit.threshold, unit.suffix)
        }
        return "\(value)"
    }

    /// Whole percents. The endpoint reports fractions, but a tenth of a percent of a
    /// weekly quota is noise the eye has to skip past on every read.
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value.rounded())
    }
}
