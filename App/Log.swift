import Foundation
import os

/// Logging for the whole app: `os.Logger` per area, plus a per-event trace
/// that exists only in Debug builds.
enum Log {
    static let subsystem = "com.ando.ModernMac"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let tap = Logger(subsystem: subsystem, category: "tap")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")

    #if DEBUG
    /// Debug builds also append the trace to this file, so a manual test run
    /// can be read back afterwards without copying log lines by hand.
    static let traceFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ModernMac/trace.log")

    private static let traceLogger = Logger(subsystem: subsystem, category: "trace")
    private static let traceQueue = DispatchQueue(label: "\(subsystem).trace", qos: .utility)

    private static let traceHandle: FileHandle? = {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: traceFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: traceFileURL.path) {
            fileManager.createFile(atPath: traceFileURL.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: traceFileURL)
        _ = try? handle?.seekToEnd()
        return handle
    }()

    private static let traceTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    #endif

    /// Per-event detail. Compiled to nothing in Release, so it is safe to call
    /// from the event tap path; in Debug the file write happens off the caller.
    static func trace(_ message: () -> String) {
        #if DEBUG
        let text = message()
        let now = Date()
        traceQueue.async {
            traceLogger.debug("\(text, privacy: .public)")
            if let data = "\(traceTimestamp.string(from: now)) \(text)\n".data(using: .utf8) {
                try? traceHandle?.write(contentsOf: data)
            }
        }
        #endif
    }
}
