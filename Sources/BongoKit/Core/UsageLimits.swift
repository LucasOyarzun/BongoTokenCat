import Foundation

/// One rate-limit window as the menu shows it: what it is called, how much of it is
/// gone, and when it starts over.
///
/// The API speaks in *utilization percent*, never in tokens — a quota is not
/// denominated in tokens because models weigh differently against it, and the
/// divisor is not published. So there is no "tokens left" to show, and this type
/// deliberately does not invent one. The token counters elsewhere in the app
/// measure spend, which is a different number that cannot be converted into this.
struct LimitWindow: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    /// 0...100. Can exceed 100 on a blown limit, so anything drawing a bar clamps.
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// A full answer from the usage endpoint, with the moment it was taken — a window
/// list alone cannot say whether it is five seconds or five hours old.
struct UsageLimits: Sendable, Equatable {
    let windows: [LimitWindow]
    let fetchedAt: Date

    var isEmpty: Bool { windows.isEmpty }
}

/// Turns the usage endpoint's JSON into `LimitWindow`s.
///
/// Two shapes are in flight at once. The original response had a fixed field per
/// window (`five_hour`, `seven_day`, `seven_day_opus`, …); the newer one
/// generalises them into a `limits` array where the per-model weekly caps live, and
/// leaves the old model-specific fields null. Accounts see one, the other, or both.
///
/// Rather than teach the UI about either, both are normalised here into one ordered
/// list. That is what makes a model this code has never heard of show up on its own
/// the day Anthropic adds it: the array entries are rendered from their own labels,
/// not matched against a list of names we would have to keep current.
enum UsageLimitsDecoder {

    /// Legacy fields win over array entries describing the same window, because
    /// they are the ones whose names we can state precisely. Anything the legacy
    /// fields cannot express — every per-model weekly cap — comes from the array.
    static func windows(from data: Data) throws -> [LimitWindow] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var windows: [LimitWindow] = []
        var claimed = Set<String>()

        let legacy = [
            (id: "session", name: "Session", window: response.fiveHour),
            (id: "weekly", name: "Weekly", window: response.sevenDay),
            (id: "weekly:opus", name: "Weekly · Opus", window: response.sevenDayOpus),
            (id: "weekly:sonnet", name: "Weekly · Sonnet", window: response.sevenDaySonnet),
        ]
        for entry in legacy {
            guard let percent = entry.window?.utilization else { continue }
            claimed.insert(entry.id)
            windows.append(LimitWindow(id: entry.id, name: entry.name,
                                       usedPercent: percent,
                                       resetsAt: date(from: entry.window?.resetsAt)))
        }

        for entry in response.limits ?? [] {
            guard let percent = entry.percent else { continue }
            let id = identity(of: entry)
            guard claimed.insert(id).inserted else { continue }
            windows.append(LimitWindow(id: id, name: name(of: entry),
                                       usedPercent: percent,
                                       resetsAt: date(from: entry.resetsAt)))
        }
        return windows
    }

    /// The key two shapes agree on, so the same window arriving in both forms is
    /// only shown once. Scoped entries key on the model, which is the only thing
    /// distinguishing one weekly cap from another.
    private static func identity(of entry: Response.Entry) -> String {
        switch entry.kind {
        case "session":  return "session"
        case "weekly_all": return "weekly"
        case "weekly_scoped": return "weekly:\(entry.modelName?.lowercased() ?? "scoped")"
        default: return entry.kind.map { "kind:\($0)" } ?? "kind:unknown"
        }
    }

    private static func name(of entry: Response.Entry) -> String {
        if let model = entry.modelName { return "Weekly · \(model)" }
        switch entry.kind {
        case "session": return "Session"
        case "weekly_all": return "Weekly"
        default: return entry.kind.map(humanised) ?? "Limit"
        }
    }

    /// `weekly_scoped` -> `Weekly scoped`. A kind we do not recognise is still worth
    /// showing; guessing at a prettier name for it is not.
    private static func humanised(_ kind: String) -> String {
        let spaced = kind.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// Reset stamps arrive with and without fractional seconds depending on the
    /// window, and `ISO8601DateFormatter` matches only the shape it was configured
    /// for — so both are tried rather than assuming one.
    static func date(from iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return fractionalParser.date(from: iso) ?? plainParser.date(from: iso)
    }

    nonisolated(unsafe) private static let fractionalParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()

    nonisolated(unsafe) private static let plainParser = ISO8601DateFormatter()

    // MARK: - Wire format

    private struct Response: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDayOpus: Window?
        let sevenDaySonnet: Window?
        let limits: [Entry]?

        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }

        struct Entry: Decodable {
            let kind: String?
            let percent: Double?
            let resetsAt: String?
            let scope: Scope?

            var modelName: String? { scope?.model?.displayName }

            struct Scope: Decodable {
                let model: Model?
                struct Model: Decodable {
                    let displayName: String?
                    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
                }
            }

            enum CodingKeys: String, CodingKey {
                case kind, percent, scope
                case resetsAt = "resets_at"
            }
        }

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
            case limits
        }
    }
}
