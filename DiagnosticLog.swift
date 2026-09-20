import Foundation

enum DiagnosticLog {
    private static let url = URL(fileURLWithPath: "/tmp/MagicMouseTap.log")
    private static let lock = NSLock()

    static func reset() {
        try? "".write(to: url, atomically: true, encoding: .utf8)
        write("app launched")
    }

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}
