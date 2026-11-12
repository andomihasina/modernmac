#if DEBUG
import Foundation
import os

/// Phase 0 spike logging: every line goes to the unified log (`make logs`) and
/// to ~/Library/Logs/ModernMac/spike.log so results can be read back afterwards.
enum SpikeLog {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ModernMac/spike.log")

    private static let logger = Logger(subsystem: "com.ando.ModernMac", category: "spike")
    private static let queue = DispatchQueue(label: "com.ando.ModernMac.spike-log", qos: .utility)

    private static let handle: FileHandle? = {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
        return handle
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// The message is built on the logging queue, so calling this from the
    /// event tap callback costs one closure and one dispatch.
    static func write(_ message: @autoclosure @escaping () -> String) {
        let now = Date()
        queue.async {
            let text = message()
            logger.log("\(text, privacy: .public)")
            if let data = "\(timestampFormatter.string(from: now)) \(text)\n".data(using: .utf8) {
                try? handle?.write(contentsOf: data)
            }
        }
    }
}
#endif
