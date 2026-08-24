import Foundation
@testable import BongoKit

/// A stand-in filesystem. Detection is the one part of the update path that reads
/// the disk, and the layout it looks for only exists on a machine that installed
/// the cask — so the layout is described here instead.
private func probe(executables: Set<String> = [],
                   directories: [String: [String]] = [:],
                   paths: [String: String] = [:]) -> FileProbe {
    FileProbe(
        isExecutable: { executables.contains($0) },
        contentsOfDirectory: { directories[$0] ?? [] },
        resolvedPath: { paths[$0] })
}

private let appPath = "/Applications/BongoTokenCat.app"
private let armCaskroom = "/opt/homebrew/Caskroom/bongo-token-cat"
private let intelCaskroom = "/usr/local/Caskroom/bongo-token-cat"

@MainActor
func runUpdateTests() {
    suite("Version parsing") {
        test("accepts the v prefix a git tag carries") {
            expectEqual(Version("v0.3.0"), Version(0, 3, 0))
        }

        test("accepts a bare version") {
            expectEqual(Version("1.2.3"), Version(1, 2, 3))
        }

        test("trims surrounding whitespace") {
            expectEqual(Version("  v2.0.1\n"), Version(2, 0, 1))
        }

        test("rejects too few and too many fields") {
            expectEqual(Version("1.2"), nil)
            expectEqual(Version("1.2.3.4"), nil)
        }

        test("rejects a field that is not a number") {
            expectEqual(Version("1.x.3"), nil)
        }

        test("rejects a signed field") {
            expectEqual(Version("1.-2.3"), nil)
        }

        test("rejects an empty field") {
            expectEqual(Version("1..3"), nil)
            expectEqual(Version(""), nil)
            expectEqual(Version("v"), nil)
        }

        test("rejects digits from other scripts") {
            expectEqual(Version("1.٢.3"), nil)
        }

        test("rejects a pre-release suffix rather than guessing its order") {
            expectEqual(Version("1.2.3-beta1"), nil)
        }
    }

    suite("Version ordering") {
        // The reason this type exists at all: lexically "0.10.0" < "0.9.0", so a
        // string comparison would tell every user on 0.9.0 they were already ahead.
        test("orders 0.10.0 after 0.9.0") {
            expect(Version(0, 10, 0) > Version(0, 9, 0), "0.10.0 must be newer than 0.9.0")
            expect("0.10.0" < "0.9.0", "the text comparison this replaces is wrong")
        }

        test("weighs major over minor and patch") {
            expect(Version(1, 0, 0) > Version(0, 99, 99), "1.0.0 must be newer than 0.99.99")
        }

        test("falls through to patch when major and minor match") {
            expect(Version(0, 3, 1) > Version(0, 3, 0), "0.3.1 must be newer than 0.3.0")
        }

        test("treats an identical version as neither newer nor older") {
            expect(!(Version(0, 3, 0) > Version(0, 3, 0)), "same version is not an update")
            expectEqual(Version(0, 3, 0), Version(0, 3, 0))
        }
    }

    suite("Release decoding") {
        test("reads the tag and the page to send people to") {
            let payload = Data("""
            {"tag_name":"v0.4.0","html_url":"https://github.com/o/r/releases/tag/v0.4.0"}
            """.utf8)
            let release = try? GitHubUpdateChecker.release(from: payload)
            expectEqual(release?.version, Version(0, 4, 0))
            expectEqual(release?.url.absoluteString, "https://github.com/o/r/releases/tag/v0.4.0")
        }

        test("ignores the rest of the payload") {
            let payload = Data("""
            {"tag_name":"v1.0.0","html_url":"https://example.com","name":"x","draft":false,"assets":[]}
            """.utf8)
            expectEqual((try? GitHubUpdateChecker.release(from: payload))?.version, Version(1, 0, 0))
        }

        test("refuses a tag it cannot parse rather than reporting no update") {
            let payload = Data("""
            {"tag_name":"nightly","html_url":"https://example.com"}
            """.utf8)
            expect((try? GitHubUpdateChecker.release(from: payload)) == nil, "unparseable tag must throw")
        }

        test("refuses a body of the wrong shape") {
            expect((try? GitHubUpdateChecker.release(from: Data("not json".utf8))) == nil,
                   "garbage must throw")
        }
    }

    suite("Install detection") {
        test("claims the install when the Caskroom links to this bundle") {
            let method = HomebrewInstall.detect(
                bundlePath: appPath,
                probe: probe(executables: ["/opt/homebrew/bin/brew"],
                             directories: [armCaskroom: [".metadata", "0.3.0"]],
                             paths: [appPath: appPath,
                                     "\(armCaskroom)/0.3.0/BongoTokenCat.app": appPath]))
            expectEqual(method, .homebrew(brewPath: "/opt/homebrew/bin/brew"))
        }

        test("finds an Intel prefix too") {
            let method = HomebrewInstall.detect(
                bundlePath: appPath,
                probe: probe(executables: ["/usr/local/bin/brew"],
                             directories: [intelCaskroom: ["0.3.0"]],
                             paths: [appPath: appPath,
                                     "\(intelCaskroom)/0.3.0/BongoTokenCat.app": appPath]))
            expectEqual(method, .homebrew(brewPath: "/usr/local/bin/brew"))
        }

        // The case the symlink check exists for: the cask is installed, but the app
        // being looked at is a build from source. Upgrading would replace the other
        // one and leave this window reporting a version that never changes.
        test("stays unmanaged when the Caskroom links to a different copy") {
            let sourceBuild = "/Users/someone/BongoTokenCat/build/BongoTokenCat.app"
            let method = HomebrewInstall.detect(
                bundlePath: sourceBuild,
                probe: probe(executables: ["/opt/homebrew/bin/brew"],
                             directories: [armCaskroom: ["0.3.0"]],
                             paths: [sourceBuild: sourceBuild,
                                     "\(armCaskroom)/0.3.0/BongoTokenCat.app": appPath]))
            expectEqual(method, .unmanaged)
        }

        test("stays unmanaged when Homebrew is not installed") {
            let method = HomebrewInstall.detect(
                bundlePath: appPath,
                probe: probe(paths: [appPath: appPath]))
            expectEqual(method, .unmanaged)
        }

        test("stays unmanaged when brew is there but the cask is not") {
            let method = HomebrewInstall.detect(
                bundlePath: appPath,
                probe: probe(executables: ["/opt/homebrew/bin/brew"],
                             paths: [appPath: appPath]))
            expectEqual(method, .unmanaged)
        }

        test("derives the Caskroom from wherever brew turned out to be") {
            expectEqual(HomebrewInstall.caskroomPath(forBrewAt: "/opt/homebrew/bin/brew"), armCaskroom)
            expectEqual(HomebrewInstall.caskroomPath(forBrewAt: "/usr/local/bin/brew"), intelCaskroom)
        }
    }
}
