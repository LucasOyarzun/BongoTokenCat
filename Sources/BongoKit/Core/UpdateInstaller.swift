import Foundation

/// Where this copy of the app came from, which is what decides whether an update
/// can be a button or only a link.
enum InstallMethod: Sendable, Equatable {
    /// Homebrew put this bundle here, and `brew` itself is at this path.
    case homebrew(brewPath: String)
    /// Built from source, or moved out from under the cask. All we can honestly
    /// offer is the release page.
    case unmanaged
}

/// The filesystem questions detection asks, gathered into one value so the real
/// answers and a test's answers are interchangeable.
struct FileProbe: Sendable {
    var isExecutable: @Sendable (String) -> Bool
    var contentsOfDirectory: @Sendable (String) -> [String]
    /// Fully resolved, or `nil` when nothing is there — a path that does not exist
    /// must not compare equal to one that does.
    var resolvedPath: @Sendable (String) -> String?

    static let live = FileProbe(
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        contentsOfDirectory: { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] },
        resolvedPath: {
            guard FileManager.default.fileExists(atPath: $0) else { return nil }
            return URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
        })
}

enum HomebrewInstall {
    static let caskName = "bongo-token-cat"
    /// Apple silicon first: it is where every Mac this app supports installs by
    /// default, so the common path costs one probe.
    static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    /// A Caskroom entry on its own is not proof. Someone can have the cask installed
    /// and still be running a build from source, and `brew upgrade` would then
    /// replace a different app than the one they are looking at. The symlink the cask
    /// leaves behind — Caskroom/<cask>/<version>/BongoTokenCat.app pointing back at
    /// /Applications — is what ties a Caskroom entry to *this* bundle.
    static func detect(bundlePath: String, probe: FileProbe = .live) -> InstallMethod {
        guard let bundle = probe.resolvedPath(bundlePath) else { return .unmanaged }
        for brewPath in brewPaths where probe.isExecutable(brewPath) {
            let caskroom = caskroomPath(forBrewAt: brewPath)
            let managesThisBundle = probe.contentsOfDirectory(caskroom).contains { version in
                probe.resolvedPath("\(caskroom)/\(version)/\(appBundleName)") == bundle
            }
            if managesThisBundle { return .homebrew(brewPath: brewPath) }
        }
        return .unmanaged
    }

    /// `/opt/homebrew/bin/brew` → `/opt/homebrew/Caskroom/<cask>`. Derived from the
    /// binary rather than hardcoded, so the Intel prefix needs no second constant.
    static func caskroomPath(forBrewAt brewPath: String) -> String {
        let binDirectory = (brewPath as NSString).deletingLastPathComponent
        let prefix = (binDirectory as NSString).deletingLastPathComponent
        return "\(prefix)/Caskroom/\(caskName)"
    }

    private static let appBundleName = "BongoTokenCat.app"
}

/// Runs `brew upgrade` in a process that outlives the app it is upgrading.
///
/// It cannot be a child of this app. The cask's `uninstall quit:` stanza makes
/// killing BongoTokenCat the *first* step of the upgrade, so a child would be
/// terminated somewhere in the middle of replacing its own bundle. Spawning a
/// detached script and then quitting on purpose turns that race into a sequence.
enum UpdateInstaller {
    static var scriptURL: URL { HookTransport.supportDirectory.appendingPathComponent("update.sh") }
    /// Where the upgrade's own output goes. A menu bar app that has just quit has
    /// nowhere to report from, so this is the only account of what happened.
    static var logURL: URL { HookTransport.supportDirectory.appendingPathComponent("update.log") }

    /// Returns once the upgrade is running. The caller is expected to quit right
    /// afterwards — the script is already waiting for it to.
    static func startUpgrade(brewPath: String, bundlePath: String) throws {
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: scriptURL.path)

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        try log.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Paths travel as arguments rather than baked into the script body. None of
        // them is user input, but a path is still not something to interpolate into
        // shell — and it keeps the script a fixed, reviewable constant.
        process.arguments = [scriptURL.path, brewPath, HomebrewInstall.caskName, bundlePath]
        process.standardOutput = log
        process.standardError = log
        try process.run()
    }

    private static let script = """
    #!/bin/bash
    # Written by BongoTokenCat. Upgrades its own cask and reopens the app.
    #
    # Runs detached from the app it replaces: `brew upgrade` quits BongoTokenCat
    # before touching the bundle, so this cannot be one of its children.
    #
    #   $1  path to brew        $2  cask name        $3  the .app to reopen
    trap '' HUP
    set -u

    # An app launched from Finder passes on a minimal environment, so the tools below
    # are not on the PATH we inherit. brew is called by absolute path.
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

    BREW="$1"
    CASK="$2"
    APP="$3"

    # "Asked to quit" and "has exited" are not the same instant, and brew will not
    # replace a bundle that is still running. Ten seconds is far past a menu bar app's
    # shutdown; past that, brew's own quit step is the backstop.
    for _ in $(seq 1 50); do
        pgrep -f "$APP/Contents/MacOS/" >/dev/null 2>&1 || break
        sleep 0.2
    done

    echo "=== upgrading $CASK ==="
    # `update` first: the cask lives in a tap that is a git clone, so without it brew
    # compares against whatever it last fetched and reports nothing to upgrade. No
    # `set -e` — a tap that failed to refresh is still worth attempting the upgrade on.
    "$BREW" update
    "$BREW" upgrade --cask "$CASK"
    status=$?
    echo "=== brew exited $status ==="

    # Reopened either way: a failed upgrade leaves the old bundle in place, and
    # leaving the user with no app at all is the worse outcome.
    open "$APP"
    exit "$status"
    """
}
