import AppKit
import Foundation

struct DiagnosticLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: Date
    let category: String
    let message: String
    let details: String?

    var formattedLogLine: String {
        let formatter = ISO8601DateFormatter()
        let dateStr = formatter.string(from: timestamp)
        if let details, !details.isEmpty {
            return "[\(dateStr)] [\(category)] \(message)\nDetails: \(details)"
        }
        return "[\(dateStr)] [\(category)] \(message)"
    }
}

@MainActor
final class AppErrorLogService: ObservableObject {
    static let shared = AppErrorLogService()

    @Published private(set) var logs: [DiagnosticLogEntry] = []

    private let maxLogCount = 200

    init() {}

    func log(category: String, message: String, details: String? = nil) {
        let entry = DiagnosticLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            category: category,
            message: message,
            details: details
        )
        logs.insert(entry, at: 0)
        if logs.count > maxLogCount {
            logs.removeLast(logs.count - maxLogCount)
        }
        #if DEBUG
        print("[\(category)] \(message) \(details ?? "")")
        #endif
    }

    func copyLogsToClipboard() {
        let text = logs.map(\.formattedLogLine).joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
