import Foundation

/// Fetching the limits, behind a protocol so the store can be driven by a stub in
/// tests without a network or an account.
protocol LimitsProviding: Sendable {
    func windows(accessToken: String) async throws -> [LimitWindow]
}

enum LimitsFetchError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case transport(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:      return "The Claude Code credential was rejected. Signing in again fixes it."
        case .rateLimited:       return "Anthropic asked us to slow down. Retrying later."
        case .http(let code):    return "Usage endpoint returned HTTP \(code)."
        case .transport:         return "Could not reach the usage endpoint."
        case .malformedResponse: return "The usage endpoint returned something unexpected."
        }
    }
}

/// Reads the same usage endpoint Claude Code's own `/usage` is built on.
///
/// It is undocumented, so everything here treats it as allowed to vanish: a failure
/// hides the section and never blocks, warns, or retries hard. The app's own job —
/// drumming cats at hook events — does not depend on a single byte of this.
struct AnthropicLimitsProvider: LimitsProviding {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Pins the OAuth beta the endpoint is gated behind. Claude Code sends the same
    /// one; without it the request is rejected outright.
    static let betaHeader = "oauth-2025-04-20"

    func windows(accessToken: String) async throws -> [LimitWindow] {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        // A cached 200 would freeze the bars at whatever they read when the response
        // was first stored, which is worse than showing nothing.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LimitsFetchError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 401, 403: throw LimitsFetchError.unauthorized
            case 429:      throw LimitsFetchError.rateLimited(retryAfter: Self.retryAfter(http))
            default:       throw LimitsFetchError.http(http.statusCode)
            }
        }

        do {
            return try UsageLimitsDecoder.windows(from: data)
        } catch {
            throw LimitsFetchError.malformedResponse
        }
    }

    /// Seconds only — the HTTP-date form of `Retry-After` is legal but has never been
    /// observed here, and guessing wrong means hammering an endpoint that just asked
    /// for room. Capped at an hour so a bad value cannot park the section for a day.
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else { return nil }
        return min(seconds, 3600)
    }
}
