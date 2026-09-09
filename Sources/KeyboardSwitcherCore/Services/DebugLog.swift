import Foundation

/// TEMPORARY DEBUG instrumentation — do not commit. Appends to /tmp/keyboard-switcher-debug.log.
public func debugLog(_ message: String) {
    let line = "\(Date()): [pid \(getpid())] \(message)\n"
    let path = "/tmp/keyboard-switcher-debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
    } else {
        try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
    }
}
