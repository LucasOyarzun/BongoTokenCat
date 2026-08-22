import Foundation
@testable import BongoKit

@MainActor
func runSkinCatalogTests() {
    suite("Skin catalog") {
        test("always unlocks the default skin") {
            expect(SkinCatalog.isUnlocked(SkinCatalog.defaultSkin, lifetimeTokens: 0),
                   "a brand new install must have something to show")
        }

        test("keeps expensive skins locked") {
            expectEqual(SkinCatalog.unlocked(lifetimeTokens: 2_000_000_000).map(\.id), ["white", "peach"])
        }

        test("reports the cheapest locked skin as next up") {
            expectEqual(SkinCatalog.nextLocked(lifetimeTokens: 2_000_000_000)?.id, "mint")
        }

        test("reports no next skin once everything is unlocked") {
            expectEqual(SkinCatalog.nextLocked(lifetimeTokens: 999_000_000_000)?.id, nil)
        }

        // Each unlock should start its bar empty rather than three quarters full,
        // which is what happens if progress is measured from zero.
        test("measures progress from the previous threshold") {
            let mint = SkinCatalog.skin(id: "mint")   // 5B, previous tier 1B

            expectClose(SkinCatalog.progress(toward: mint, lifetimeTokens: 1_000_000_000), 0)
            expectClose(SkinCatalog.progress(toward: mint, lifetimeTokens: 3_000_000_000), 0.5)
        }

        test("clamps progress into 0...1") {
            let peach = SkinCatalog.skin(id: "peach")

            expectClose(SkinCatalog.progress(toward: peach, lifetimeTokens: 0), 0)
            expectClose(SkinCatalog.progress(toward: peach, lifetimeTokens: 99_000_000_000), 1)
        }

        test("falls back to the default for an unknown skin id") {
            expectEqual(SkinCatalog.skin(id: "does-not-exist").id, SkinCatalog.defaultSkin.id)
        }

        test("orders thresholds ascending") {
            let thresholds = SkinCatalog.all.map(\.tokensRequired)
            expectEqual(thresholds, thresholds.sorted(), "the unlock ladder must only go up")
        }
    }
}

@MainActor
func runOverlayLayoutTests() {
    suite("Overlay layout") {
        test("lays out a single row when everything fits") {
            let grid = OverlayLayout.grid(count: 3, catWidth: 200, showsLabel: true, screenWidth: 1512)

            expectEqual(grid.columns, 3)
            expectEqual(grid.rows, 1)
        }

        // Thirteen workspaces at full size are wider than any screen. Wrapping keeps
        // them on screen instead of running off the edge.
        test("wraps to more rows when a single row would overflow") {
            let grid = OverlayLayout.grid(count: 13, catWidth: 200, showsLabel: true, screenWidth: 1512)

            expect(grid.columns < 13, "13 cats at 200pt cannot fit one 1512pt row")
            expect(grid.rows > 1, "the overflow has to go somewhere")
            expect(grid.size.width <= 1512 * 0.9, "the overlay must not span the whole screen")
        }

        test("always keeps at least one column") {
            expectEqual(OverlayLayout.grid(count: 4, catWidth: 4000, showsLabel: false, screenWidth: 800).columns, 1)
        }

        test("collapses to nothing with no agents") {
            expectEqual(OverlayLayout.grid(count: 0, catWidth: 200, showsLabel: true, screenWidth: 1512).size, .zero)
        }

        test("reserves label height only when labels are shown") {
            let withLabel = OverlayLayout.cellSize(catWidth: 200, showsLabel: true)
            let without = OverlayLayout.cellSize(catWidth: 200, showsLabel: false)

            expectClose(withLabel.height - without.height, OverlayLayout.labelHeight)
        }

        test("anchors to the requested corner") {
            let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
            let size = CGSize(width: 200, height: 100)

            let bottomRight = OverlayLayout.origin(for: size, in: screen, anchor: .bottomTrailing)
            let topLeft = OverlayLayout.origin(for: size, in: screen, anchor: .topLeading)

            expectClose(bottomRight.x, 1000 - 200 - 16)
            expectClose(bottomRight.y, 16)
            expectClose(topLeft.x, 16)
            expectClose(topLeft.y, 800 - 100 - 16)
        }
    }
}

@MainActor
func runTokenReaderTests() {
    suite("Token reader") {
        test("sums every token field") {
            let line = """
            {"type":"assistant","timestamp":"2026-08-21T10:00:00.000Z","requestId":"r1",\
            "message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":20,\
            "cache_creation_input_tokens":5,"cache_read_input_tokens":100}}}
            """

            expectEqual(TokenReader.parse(line)?.tokens, 135)
        }

        test("ignores lines that are not assistant turns") {
            expectEqual(TokenReader.parse(#"{"type":"user","message":{"usage":{"input_tokens":10}}}"#)?.tokens, nil)
        }

        // Resumed sessions and sidechains write the same turn to several files. The
        // identity is what stops it being counted twice.
        test("builds a stable identity from message and request ids") {
            let line = """
            {"type":"assistant","timestamp":"2026-08-21T10:00:00.000Z","requestId":"r1",\
            "message":{"id":"m1","usage":{"output_tokens":5}}}
            """

            expectEqual(TokenReader.parse(line)?.id, "m1|r1")
        }

        test("falls back to the timestamp when no ids are present") {
            let line = """
            {"type":"assistant","timestamp":"2026-08-21T10:00:00.000Z",\
            "message":{"usage":{"output_tokens":5}}}
            """

            expectEqual(TokenReader.parse(line)?.id, "2026-08-21T10:00:00.000Z")
        }

        test("skips turns that spent nothing") {
            let line = #"{"type":"assistant","timestamp":"2026-08-21T10:00:00.000Z","message":{"id":"m","usage":{}}}"#

            expectEqual(TokenReader.parse(line)?.tokens, nil)
        }

        test("formats counts compactly") {
            expectEqual(TokenFormatter.compact(7_056_374_994), "7.1B")
            expectEqual(TokenFormatter.compact(428_000_000), "428.0M")
            expectEqual(TokenFormatter.compact(12_400), "12.4K")
            expectEqual(TokenFormatter.compact(42), "42")
        }
    }
}

@MainActor
func runTokenReaderPerformanceTests() {
    suite("Token reader — scan cost") {
        // Regression guard for the bug that pinned a core: a date formatter was
        // built for every line of a 457-file history.
        test("skips date parsing for timestamps that cannot be today") {
            let old = """
            {"type":"assistant","timestamp":"2020-01-02T10:00:00.000Z","requestId":"r",\
            "message":{"id":"m","usage":{"output_tokens":5}}}
            """

            let entry = TokenReader.parse(old, recentUTCDays: ["2026-08-22"])

            expectEqual(entry?.day, "2020-01-02", "an old line should use its raw UTC prefix")
        }

        test("converts precisely for timestamps inside the window") {
            let line = """
            {"type":"assistant","timestamp":"2026-08-22T10:00:00.000Z","requestId":"r",\
            "message":{"id":"m","usage":{"output_tokens":5}}}
            """

            let entry = TokenReader.parse(line, recentUTCDays: ["2026-08-22"])

            expectEqual(entry?.day, TokenReader.localDay(ofISO: "2026-08-22T10:00:00.000Z"))
        }

        test("spans three UTC days so any local timezone is covered") {
            let days = TokenReader.utcDaysOverlappingLocalToday(Date())

            expectEqual(days.count, 3, "±1 day covers every UTC offset from -12 to +14")
        }

        test("scans a realistic history quickly") {
            let line = """
            {"type":"assistant","timestamp":"2026-08-01T10:00:00.000Z","requestId":"r",\
            "message":{"id":"m","usage":{"input_tokens":10,"output_tokens":20}}}
            """
            let recent = TokenReader.utcDaysOverlappingLocalToday(Date())

            let started = Date()
            for _ in 0..<20_000 { _ = TokenReader.parse(line, recentUTCDays: recent) }
            let elapsed = Date().timeIntervalSince(started)

            expect(elapsed < 2.0, "20k lines took \(String(format: "%.2f", elapsed))s — the scan is back on the slow path")
        }
    }
}

@MainActor
func runUsageCacheTests() {
    suite("Usage cache") {
        test("reuses an entry whose fingerprint is unchanged") {
            let when = Date(timeIntervalSince1970: 1_700_000_000)
            let usage = FileUsage(modified: when, size: 42, total: 100, byDay: [:])

            expect(usage.matches(modified: when, size: 42), "same file must hit the cache")
        }

        test("invalidates when the file grew") {
            let when = Date(timeIntervalSince1970: 1_700_000_000)
            let usage = FileUsage(modified: when, size: 42, total: 100, byDay: [:])

            expect(!usage.matches(modified: when, size: 43), "an appended transcript must be re-read")
        }

        test("invalidates when the file was touched") {
            let when = Date(timeIntervalSince1970: 1_700_000_000)
            let usage = FileUsage(modified: when, size: 42, total: 100, byDay: [:])

            expect(!usage.matches(modified: when.addingTimeInterval(5), size: 42),
                   "a newer modification time must be re-read")
        }

        // JSON round-tripping loses sub-second precision, which would otherwise
        // invalidate every entry on every scan and defeat the cache entirely.
        test("tolerates sub-second drift in the modification time") {
            let when = Date(timeIntervalSince1970: 1_700_000_000.4)
            let usage = FileUsage(modified: when, size: 42, total: 100, byDay: [:])

            expect(usage.matches(modified: Date(timeIntervalSince1970: 1_700_000_000.9), size: 42),
                   "sub-second jitter is not a change")
        }

        test("survives a JSON round trip") {
            let usage = FileUsage(modified: Date(timeIntervalSince1970: 1_700_000_000),
                                  size: 42, total: 100, byDay: ["2026-08-22": 7])

            guard let data = try? JSONEncoder().encode(["a": usage]),
                  let back = try? JSONDecoder().decode([String: FileUsage].self, from: data) else {
                expect(false, "cache must round trip through JSON")
                return
            }
            expectEqual(back["a"], usage)
        }
    }
}

@MainActor
func runOverlayInteractionTests() {
    suite("Overlay interaction") {
        // Only the cats take the mouse. If the whole panel did, the gaps between
        // cats would swallow clicks meant for the window behind them.
        test("gives every cat its own hit rect") {
            let cells = OverlayLayout.cellFrames(count: 3, columns: 3, catWidth: 100, showsLabel: true)

            expectEqual(cells.count, 3)
            expect(cells[0].maxX <= cells[1].minX, "cats must not overlap")
            expectClose(cells[1].minX - cells[0].maxX, OverlayLayout.spacing)
        }

        test("stacks hit rects into rows when the grid wraps") {
            let cells = OverlayLayout.cellFrames(count: 4, columns: 2, catWidth: 100, showsLabel: true)

            expectClose(cells[0].minY, cells[1].minY, tolerance: 0.001, "same row")
            expect(cells[2].minY > cells[0].minY, "second row sits below the first")
        }

        test("keeps hit rects inside the panel it measured") {
            let grid = OverlayLayout.grid(count: 5, catWidth: 90, showsLabel: true, screenWidth: 1512)
            let cells = OverlayLayout.cellFrames(count: 5, columns: grid.columns,
                                                 catWidth: 90, showsLabel: true)

            for cell in cells {
                expect(cell.maxX <= grid.size.width + 0.001, "cell \(cell) escapes width \(grid.size.width)")
                expect(cell.maxY <= grid.size.height + 0.001, "cell \(cell) escapes height \(grid.size.height)")
            }
        }

        test("returns no hit rects with no cats") {
            expect(OverlayLayout.cellFrames(count: 0, columns: 0, catWidth: 100, showsLabel: true).isEmpty,
                   "nothing to hit")
        }

        // Adding cats grows the panel; a dragged overlay must not be pushed out of
        // reach as a result.
        test("clamps a dragged overlay back into reach") {
            let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
            let size = CGSize(width: 300, height: 120)

            let farRight = OverlayLayout.clamp(origin: CGPoint(x: 5000, y: 400), size: size, to: screen)
            let farLeft = OverlayLayout.clamp(origin: CGPoint(x: -5000, y: 400), size: size, to: screen)

            expect(farRight.x < screen.maxX, "must keep a grabbable sliver on screen")
            expect(farLeft.x + size.width > screen.minX, "must not vanish off the left edge")
        }

        test("leaves an on-screen position untouched") {
            let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
            let origin = CGPoint(x: 400, y: 300)

            expectEqual(OverlayLayout.clamp(origin: origin, size: CGSize(width: 200, height: 100), to: screen),
                        origin)
        }

        test("offers a size range that goes genuinely small") {
            expect(Settings.minimumCatWidth <= 48, "the point of the slider is that cats can be tiny")
            expect(Settings.defaultCatWidth < 120, "the old 200pt default was too big to live with")
        }
    }
}
