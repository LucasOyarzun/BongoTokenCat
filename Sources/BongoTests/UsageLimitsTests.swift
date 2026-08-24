import Foundation
@testable import BongoKit

@MainActor
func runUsageLimitsTests() {
    suite("Usage limit decoding") {
        test("reads the original per-field shape") {
            let windows = decode("""
            {"five_hour": {"utilization": 2.5, "resets_at": "2026-08-23T22:00:00Z"},
             "seven_day": {"utilization": 18, "resets_at": "2026-08-27T00:00:00Z"}}
            """)

            expectEqual(windows.map(\.name), ["Session", "Weekly"])
            expectClose(windows.first?.usedPercent ?? -1, 2.5)
        }

        test("reads the generalised limits array") {
            let windows = decode("""
            {"limits": [
              {"kind": "session", "percent": 2, "resets_at": "2026-08-23T22:00:00Z"},
              {"kind": "weekly_all", "percent": 18, "resets_at": "2026-08-27T00:00:00Z"}]}
            """)

            expectEqual(windows.map(\.name), ["Session", "Weekly"])
        }

        // The whole point of rendering the array generically: a model nobody wrote
        // code for still gets a row.
        test("names a model-scoped weekly window after its model") {
            let windows = decode("""
            {"limits": [
              {"kind": "weekly_scoped", "percent": 7,
               "scope": {"model": {"display_name": "Claude Fable 5"}}}]}
            """)

            expectEqual(windows.map(\.name), ["Weekly · Claude Fable 5"])
        }

        // Accounts mid-migration get both shapes at once, and a session bar shown
        // twice reads as two different limits.
        test("does not show the same window twice when both shapes arrive") {
            let windows = decode("""
            {"five_hour": {"utilization": 2, "resets_at": "2026-08-23T22:00:00Z"},
             "seven_day": {"utilization": 18, "resets_at": "2026-08-27T00:00:00Z"},
             "limits": [
              {"kind": "session", "percent": 2},
              {"kind": "weekly_all", "percent": 18},
              {"kind": "weekly_scoped", "percent": 7,
               "scope": {"model": {"display_name": "Opus"}}}]}
            """)

            expectEqual(windows.map(\.name), ["Session", "Weekly", "Weekly · Opus"])
        }

        test("skips windows the account does not have") {
            let windows = decode("""
            {"five_hour": {"utilization": 2}, "seven_day_opus": null, "seven_day_sonnet": null}
            """)

            expectEqual(windows.map(\.name), ["Session"])
        }

        test("keeps a kind it does not recognise rather than dropping it") {
            let windows = decode("""
            {"limits": [{"kind": "monthly_all", "percent": 3}]}
            """)

            expectEqual(windows.map(\.name), ["Monthly all"])
        }

        test("reports no windows for an account that has none") {
            expectEqual(decode("{}").count, 0)
        }

        test("refuses a body that is not the usage endpoint's") {
            var threw = false
            do { _ = try UsageLimitsDecoder.windows(from: Data("[1,2,3]".utf8)) } catch { threw = true }
            expect(threw, "a garbage body has to fail loudly, not decode to an empty list")
        }
    }

    suite("Usage limit reset stamps") {
        test("parses a stamp with fractional seconds") {
            let parsed = UsageLimitsDecoder.date(from: "2026-08-23T22:00:00.123Z")
            expectEqual(parsed?.timeIntervalSince1970.rounded(), 1787522400)
        }

        test("parses a stamp without fractional seconds") {
            let parsed = UsageLimitsDecoder.date(from: "2026-08-23T22:00:00Z")
            expectEqual(parsed?.timeIntervalSince1970.rounded(), 1787522400)
        }

        test("survives a window with no reset stamp") {
            expectEqual(UsageLimitsDecoder.date(from: nil), nil)
            expectEqual(UsageLimitsDecoder.date(from: ""), nil)
        }
    }

    suite("Limit windows") {
        test("reports what is left of a used window") {
            let window = LimitWindow(id: "session", name: "Session", usedPercent: 17, resetsAt: nil)
            expectClose(window.remainingPercent, 83)
        }

        // A blown limit reports past 100, and "-4% left" is not a thing.
        test("never reports a negative remainder") {
            let window = LimitWindow(id: "session", name: "Session", usedPercent: 104, resetsAt: nil)
            expectClose(window.remainingPercent, 0)
        }

        test("rounds percentages to whole numbers") {
            expectEqual(TokenFormatter.percent(82.6), "83%")
            expectEqual(TokenFormatter.percent(0.4), "0%")
        }
    }

    suite("Claude credentials") {
        test("reads the access token out of the credential shape") {
            let credential = ClaudeCredentials.parse(Data("""
            {"claudeAiOauth": {"accessToken": "token-value", "expiresAt": 4102444800000}}
            """.utf8), source: .file)

            expectEqual(credential?.accessToken, "token-value")
            expect(credential?.isUsable == true, "an expiry in 2100 is usable")
        }

        // Signed out writes an explicit null here, which a nil check would read as
        // "present" once JSONSerialization turns it into NSNull.
        test("treats a signed-out credential as having no account") {
            let data = Data(#"{"claudeAiOauth": null}"#.utf8)

            expectEqual(ClaudeCredentials.parse(data, source: .file)?.accessToken, nil)
            expect(!ClaudeCredentials.hasAccountSection(data), "explicit null is not an account")
        }

        test("accepts an expiry written in seconds") {
            let credential = ClaudeCredentials.parse(Data("""
            {"claudeAiOauth": {"accessToken": "t", "expiresAt": 4102444800}}
            """.utf8), source: .file)

            expect(credential?.isUsable == true, "seconds and milliseconds must both land in 2100")
        }

        test("refuses a token that expires within the minute") {
            let almostGone = Date().addingTimeInterval(30).timeIntervalSince1970
            let credential = ClaudeCredentials.parse(Data("""
            {"claudeAiOauth": {"accessToken": "t", "expiresAt": \(almostGone)}}
            """.utf8), source: .file)

            expect(credential?.isUsable == false, "a token that dies mid-request is not usable")
        }

        // The source travels with the token so a rejected one can be blamed on where
        // it came from — a dead file token has to stop being retried.
        test("remembers which source a credential came from") {
            let data = Data(#"{"claudeAiOauth": {"accessToken": "t"}}"#.utf8)

            expectEqual(ClaudeCredentials.parse(data, source: .file)?.source, .file)
            expectEqual(ClaudeCredentials.parse(data, source: .keychain)?.source, .keychain)
        }

        test("accepts a token with no expiry at all") {
            let credential = ClaudeCredentials.parse(Data("""
            {"claudeAiOauth": {"accessToken": "t"}}
            """.utf8), source: .file)

            expect(credential?.isUsable == true, "no expiry means nothing says it is dead")
        }

        test("ignores a credential file with no token") {
            let empty = Data(#"{"claudeAiOauth": {"accessToken": ""}}"#.utf8)
            expectEqual(ClaudeCredentials.parse(empty, source: .file)?.accessToken, nil)
        }
    }

    suite("Limits transport") {
        test("honours a Retry-After in seconds") {
            expectEqual(AnthropicLimitsProvider.retryAfter(response(retryAfter: "120")), 120)
        }

        // A server that says "come back tomorrow" would otherwise park the section
        // for the rest of the day.
        test("caps an absurd Retry-After at an hour") {
            expectEqual(AnthropicLimitsProvider.retryAfter(response(retryAfter: "86400")), 3600)
        }

        test("ignores a Retry-After it cannot read") {
            expectEqual(AnthropicLimitsProvider.retryAfter(response(retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT")), nil)
            expectEqual(AnthropicLimitsProvider.retryAfter(response(retryAfter: "-5")), nil)
            expectEqual(AnthropicLimitsProvider.retryAfter(response(retryAfter: nil)), nil)
        }
    }
}

@MainActor
private func decode(_ json: String, file: StaticString = #fileID, line: UInt = #line) -> [LimitWindow] {
    do {
        return try UsageLimitsDecoder.windows(from: Data(json.utf8))
    } catch {
        expect(false, "decoding failed: \(error)", file: file, line: line)
        return []
    }
}

private func response(retryAfter: String?) -> HTTPURLResponse {
    HTTPURLResponse(url: AnthropicLimitsProvider.endpoint,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: retryAfter.map { ["Retry-After": $0] })!
}
