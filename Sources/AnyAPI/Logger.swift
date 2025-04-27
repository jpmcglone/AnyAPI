import Foundation

enum LogLevel: String {
  case debug = "🔹"
  case info = "ℹ️"
  case warning = "⚠️"
  case error = "🛑"
  case success = "✅"
  case event = "🛜"
}

struct Logger {
  static func log(_ message: String, level: LogLevel = .info, category: String = "General") {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("\(level.rawValue) [\(category)] \(timestamp): \(message)")
  }
}
