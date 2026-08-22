import Foundation

/// Append-only diagnostic log. A menu bar app has no console, and the hook path
/// fails silently by design, so without this a broken install looks identical to
/// an idle one.
enum AppLog {
    private static let queue = DispatchQueue(label: "bongotokenbar.log")
    private static let maxBytes = 512 * 1024

    static var fileURL: URL { HookTransport.supportDirectory.appendingPathComponent("bongotokenbar.log") }

    nonisolated(unsafe) private static let stampFormatter = ISO8601DateFormatter()

    static func write(_ message: String) {
        queue.async {
            let stamp = stampFormatter.string(from: Date())
            guard let line = "\(stamp) \(message)\n".data(using: .utf8) else { return }
            rotateIfNeeded()
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                _ = try? line.write(to: fileURL, options: .atomic)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    /// Truncate rather than rotate into numbered files: this log is for reading the
    /// last few minutes after something misbehaved, not for history.
    private static func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
