import Foundation
import PDFKit

@MainActor
final class AITokenSwapService: ObservableObject {
    static let shared = AITokenSwapService()

    @Published private(set) var activeSessions: [TokenSwapSession] = []

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var sessionsDirectory: URL {
        let dir = home.appendingPathComponent("Library/Application Support/com.storagepal.mac/TokenSessions")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        loadSessions()
    }

    // MARK: - Forward Pass (Token Creation)

    func createSession(
        documentName: String,
        template: RedactionTemplateKind,
        matches: [SensitiveEntityMatch]
    ) -> TokenSwapSession {
        var tokenMap: [String: String] = [:]
        var realToTokenMap: [String: String] = [:]

        for match in matches where match.isEnabled {
            tokenMap[match.tokenReplacement] = match.originalText
            realToTokenMap[match.originalText] = match.tokenReplacement
        }

        let session = TokenSwapSession(
            id: UUID().uuidString,
            documentName: documentName,
            template: template.rawValue,
            createdAt: Date(),
            tokenMap: tokenMap,
            realToTokenMap: realToTokenMap
        )

        activeSessions.insert(session, at: 0)
        saveSession(session)
        return session
    }

    // MARK: - Reverse Pass (Restoration from AI)

    func restoreRealData(aiResponseText: String, session: TokenSwapSession) -> (restoredText: String, replacementsCount: Int) {
        var result = aiResponseText
        var count = 0

        // Sort tokens by length descending to prevent partial match collisions
        let sortedTokens = session.tokenMap.keys.sorted { $0.count > $1.count }

        for token in sortedTokens {
            guard let realValue = session.tokenMap[token] else { continue }
            if result.contains(token) {
                result = result.replacingOccurrences(of: token, with: realValue)
                count += 1
            }
        }

        return (result, count)
    }

    func restorePDF(aiPDFURL: URL, session: TokenSwapSession, targetURL: URL) throws -> Int {
        guard let pdf = PDFDocument(url: aiPDFURL) else {
            throw NSError(domain: "AITokenSwapService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF."])
        }

        var replacements = 0
        let sortedTokens = session.tokenMap.keys.sorted { $0.count > $1.count }

        for token in sortedTokens {
            guard let realValue = session.tokenMap[token] else { continue }
            let selections = pdf.findString(token, withOptions: .caseInsensitive)
            for selection in selections {
                guard let page = selection.pages.first else { continue }
                let bounds = selection.bounds(for: page)

                // Render replacement text over token region
                let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
                annotation.contents = realValue
                annotation.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
                annotation.fontColor = .systemGreen
                annotation.color = .white
                page.addAnnotation(annotation)
                replacements += 1
            }
        }

        guard pdf.write(to: targetURL) else {
            throw NSError(domain: "AITokenSwapService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to save restored PDF."])
        }

        return replacements
    }

    // MARK: - Session Storage

    func deleteSession(id: String) {
        let file = sessionsDirectory.appendingPathComponent("\(id).json")
        try? fm.removeItem(at: file)
        activeSessions.removeAll { $0.id == id }
    }

    private func saveSession(_ session: TokenSwapSession) {
        let file = sessionsDirectory.appendingPathComponent("\(session.id).json")
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func loadSessions() {
        guard let files = try? fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else { return }
        var loaded: [TokenSwapSession] = []
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let session = try? JSONDecoder().decode(TokenSwapSession.self, from: data) {
                if session.createdAt < thirtyDaysAgo {
                    try? fm.removeItem(at: file)
                } else {
                    loaded.append(session)
                }
            }
        }

        self.activeSessions = loaded.sorted { $0.createdAt > $1.createdAt }
    }
}
