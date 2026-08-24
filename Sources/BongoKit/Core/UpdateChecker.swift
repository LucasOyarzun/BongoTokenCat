import Foundation

/// A published release, reduced to the two things the menu needs: which version it
/// is, and where to read about it.
struct Release: Sendable, Equatable {
    let version: Version
    let url: URL
}

/// Behind a protocol so the model can be driven by a stub in tests, without a
/// network and without depending on what happens to be the latest release today.
protocol UpdateChecking: Sendable {
    func latestRelease() async throws -> Release
}

enum UpdateCheckError: LocalizedError, Equatable {
    case rateLimited
    case http(Int)
    case transport(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited:       return "GitHub asked us to slow down. Checking again later."
        case .http(let code):    return "GitHub returned HTTP \(code)."
        case .transport:         return "Could not reach GitHub."
        case .malformedResponse: return "GitHub returned something unexpected."
        }
    }
}

/// Reads the public releases API.
///
/// Unauthenticated on purpose. The endpoint needs no token, and storing a
/// credential to learn a version number that is already public would be a far worse
/// trade than the sixty-requests-an-hour ceiling it buys — this asks twice a day.
/// `releases/latest` also filters drafts and pre-releases server-side, so nothing
/// here has to.
struct GitHubUpdateChecker: UpdateChecking {
    static let endpoint = URL(string: "https://api.github.com/repos/LucasOyarzun/BongoTokenCat/releases/latest")!

    func latestRelease() async throws -> Release {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // A cached 200 would pin the app to whatever was current the first time it
        // asked, which is the one thing an update check must never do.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateCheckError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // GitHub spends an exhausted rate limit as a 403 with the remaining count
            // at zero rather than as a 429, so the header is the only thing that
            // tells it apart from a genuine refusal.
            let exhausted = http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
            throw exhausted ? UpdateCheckError.rateLimited : UpdateCheckError.http(http.statusCode)
        }
        return try Self.release(from: data)
    }

    /// Split from the request so the payload's shape is testable without one.
    static func release(from data: Data) throws -> Release {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let version = Version(payload.tagName),
              let url = URL(string: payload.htmlURL) else {
            throw UpdateCheckError.malformedResponse
        }
        return Release(version: version, url: url)
    }

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
