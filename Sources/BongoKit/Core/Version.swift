import Foundation

/// A three-field semantic version.
///
/// Compared field by field rather than as text, which is not a detail: "0.10.0"
/// sorts *before* "0.9.0" lexically, so a string comparison would tell everyone
/// still on 0.9.0 that they were already ahead of the release meant to replace it.
struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Tolerates the leading `v` a git tag carries. Everything else is rejected,
    /// pre-release suffixes included: this project does not publish them, and
    /// ordering them correctly needs rules that would go untested here.
    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("v") ? trimmed.dropFirst() : trimmed[...]
        let fields = body.split(separator: ".", omittingEmptySubsequences: false).compactMap(Self.field)
        guard fields.count == 3 else { return nil }
        self.init(fields[0], fields[1], fields[2])
    }

    /// ASCII digits only. `Character.isNumber` also accepts other scripts' digits,
    /// which `Int` then refuses, and allowing a sign would let "1.-2.0" through.
    private static func field(_ raw: Substring) -> Int? {
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(raw)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// What the running bundle reports.
    ///
    /// `nil` for anything without an Info.plist — `swift run` during development,
    /// mainly — and the update check sits out the round rather than guessing which
    /// version it is looking at. An assembled .app always has one.
    static var current: Version? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(Version.init)
    }
}
