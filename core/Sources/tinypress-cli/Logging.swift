import Foundation

/// Tiny logger for the CLI. Stays out of the way of `stdout` so the binary
/// can be embedded in scripts that pipe results.
enum Log {
    /// Write a status message to `stderr`.
    static func info(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    /// Write an error message to `stderr` with an `error:` prefix.
    static func error(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}
