import Foundation

/// Appends timestamped lines to ~/Library/Logs/Hingewave.log and echoes them to
/// stderr when attached to a terminal. Never logs screen content.
enum Log {
    private static let queue = DispatchQueue(label: "com.antlib.hingewave.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let url: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("Hingewave.log")
    }()
    private static let echo = isatty(STDERR_FILENO) != 0

    static func info(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            if echo { FileHandle.standardError.write(Data(line.utf8)) }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
