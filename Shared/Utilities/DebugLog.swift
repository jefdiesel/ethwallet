import Foundation

/// Debug logging utility - only prints in DEBUG builds
/// Use instead of print() for development logs that shouldn't appear in release
enum DebugLog {
    /// Log a message with a tag prefix
    /// - Parameters:
    ///   - tag: Short identifier like "Bundler", "SendVM", etc.
    ///   - message: The message to log
    static func log(_ tag: String, _ message: String) {
        #if DEBUG
        print("[\(tag)] \(message)")
        #endif
    }

    /// Log with automatic function/line info
    static func trace(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        print("[\(filename):\(line)] \(function) - \(message)")
        #endif
    }
}
