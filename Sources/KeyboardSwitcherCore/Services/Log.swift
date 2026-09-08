import Foundation

public func logError(_ message: String) {
    FileHandle.standardError.write(Data("keyboard-switcher: \(message)\n".utf8))
}
