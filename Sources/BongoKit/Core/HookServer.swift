import Foundation
import Network

/// Where the hook script and the app agree to meet.
///
/// The port is discovered rather than fixed because a second copy of the app (or
/// anything else on the machine) may already hold the first choice. Whichever port
/// the app wins gets written to `runtime.json`, which is how the hook finds it.
enum HookTransport {
    static let ports: [UInt16] = [41430, 41431, 41432, 41433, 41434]
    static let tokenHeader = "x-bongo-token"

    static var supportDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bongotokencat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var runtimeFile: URL { supportDirectory.appendingPathComponent("runtime.json") }
    static var hookScript: URL { supportDirectory.appendingPathComponent("bongo-hook.sh") }

    struct Runtime: Codable { let port: UInt16; let token: String }

    /// The shared secret lives in the runtime file, which is readable only by the
    /// user. It is not protecting secrets — it stops any other local process from
    /// puppeting the cats through an open localhost port.
    static func makeToken() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    static func publish(_ runtime: Runtime) throws {
        let data = try JSONEncoder().encode(runtime)
        try data.write(to: runtimeFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: runtimeFile.path)
    }

    static func clearRuntime() { try? FileManager.default.removeItem(at: runtimeFile) }
}

/// Minimal localhost HTTP endpoint that accepts hook payloads.
///
/// Written against `NWListener` rather than a web framework because the whole
/// protocol is "POST one small JSON, answer 204": a dependency would cost more
/// than it saves, and hooks block Claude Code while they run so the path has to
/// stay short.
@MainActor
final class HookServer {
    private var listener: NWListener?
    private let token = HookTransport.makeToken()
    private let handler: ConnectionHandler

    init(onEvent: @escaping @Sendable (HookEvent) -> Void) {
        self.handler = ConnectionHandler(token: token, onEvent: onEvent)
    }

    func start() throws {
        for port in HookTransport.ports {
            let listener: NWListener
            do {
                listener = try makeListener(on: port)
            } catch {
                AppLog.write("port \(port) unavailable: \(error)")
                continue
            }
            self.listener = listener
            listener.start(queue: .global(qos: .userInitiated))
            try HookTransport.publish(.init(port: port, token: token))
            AppLog.write("hook server listening on 127.0.0.1:\(port)")
            return
        }
        throw HookServerError.noPortAvailable
    }

    func stop() {
        listener?.cancel()
        listener = nil
        HookTransport.clearRuntime()
    }

    /// Binds to loopback only. The port comes from `requiredLocalEndpoint` rather
    /// than `NWListener(using:on:)` — passing both makes the listener fail to bind.
    private func makeListener(on port: UInt16) throws -> NWListener {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw HookServerError.noPortAvailable }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = false
        let listener = try NWListener(using: parameters)
        let handler = self.handler
        listener.newConnectionHandler = { connection in handler.serve(connection) }
        // Binding happens asynchronously after start(), so a port conflict surfaces
        // here rather than as a thrown error. Without this the app would look fine
        // while silently receiving nothing.
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { AppLog.write("listener on \(port) failed: \(error)") }
        }
        return listener
    }
}

/// Serves one connection: read a POST, authenticate it, decode it, answer 204.
///
/// Split out of `HookServer` because Network delivers callbacks on its own queue,
/// and everything they touch has to be `Sendable`. Holding only a token and a
/// closure makes that trivially true.
private struct ConnectionHandler: Sendable {
    let token: String
    let onEvent: @Sendable (HookEvent) -> Void

    /// Hooks run on Claude Code's critical path. Anything slower than this is a
    /// stall the user feels, so a stuck connection is dropped rather than served.
    private static let connectionTimeout: TimeInterval = 2
    private static let maxBodyBytes = 256 * 1024

    func serve(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.connectionTimeout) { connection.cancel() }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { chunk, _, isComplete, error in
            guard error == nil else { connection.cancel(); return }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            guard buffer.count <= Self.maxBodyBytes else { connection.cancel(); return }

            if let request = HTTPRequest(buffer) {
                handle(request, on: connection)
                return
            }
            guard !isComplete else { connection.cancel(); return }
            receive(on: connection, buffer: buffer)
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        defer { respondNoContent(on: connection) }
        guard request.header(HookTransport.tokenHeader) == token else {
            AppLog.write("rejected hook post with bad token")
            return
        }
        guard let event = try? JSONDecoder().decode(HookEvent.self, from: request.body) else {
            AppLog.write("undecodable hook payload (\(request.body.count) bytes)")
            return
        }
        onEvent(event)
    }

    /// 204 rather than 200: the hook discards the body anyway, and sending nothing
    /// keeps the response inside a single packet.
    private func respondNoContent(on connection: NWConnection) {
        let response = Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

enum HookServerError: Error { case noPortAvailable }

/// Just enough HTTP to read one small POST. Returns nil while the request is still
/// arriving so the caller knows to keep reading.
struct HTTPRequest {
    let headers: [String: String]
    let body: Data

    init?(_ raw: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = raw.firstRange(of: separator) else { return nil }
        let headerText = String(decoding: raw[raw.startIndex..<headerEnd.lowerBound], as: UTF8.self)

        var headers: [String: String] = [:]
        for line in headerText.split(separator: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let declared = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerEnd.upperBound
        let available = raw.count - raw.distance(from: raw.startIndex, to: bodyStart)
        guard available >= declared else { return nil }

        self.headers = headers
        self.body = Data(raw[bodyStart...].prefix(declared))
    }

    func header(_ name: String) -> String? { headers[name.lowercased()] }
}
