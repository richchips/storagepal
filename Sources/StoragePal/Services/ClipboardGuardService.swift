import AppKit
import Foundation

@MainActor
final class ClipboardGuardService: ObservableObject {
    static let shared = ClipboardGuardService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "StoragePalClipboardGuardEnabled")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    @Published private(set) var detectedSensitiveItem: ClipboardSensitiveItem?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "StoragePalClipboardGuardEnabled") as? Bool ?? true
        if isEnabled {
            startMonitoring()
        }
    }

    func startMonitoring() {
        stopMonitoring()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.inspectClipboard()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func inspectClipboard() {
        guard isEnabled else { return }
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            detectedSensitiveItem = nil
            return
        }

        if let item = analyzeTextForSecrets(string) {
            self.detectedSensitiveItem = item
        } else {
            self.detectedSensitiveItem = nil
        }
    }

    // MARK: - Actions

    func sanitizeClipboard() {
        guard let item = detectedSensitiveItem else { return }
        var sanitized = item.rawText

        switch item.kind {
        case .openAIKey:
            sanitized = "sk-************************************"
        case .anthropicKey:
            sanitized = "sk-ant-********************************"
        case .awsKey:
            sanitized = "AKIA****************"
        case .githubToken:
            sanitized = "ghp_********************************"
        case .privateKey:
            sanitized = "-----BEGIN PRIVATE KEY-----\n[SANITIZED_KEY_MATERIAL]\n-----END PRIVATE KEY-----"
        case .creditCard:
            let last4 = String(item.rawText.suffix(4))
            sanitized = "****-****-****-\(last4)"
        case .ssn:
            let last4 = String(item.rawText.suffix(4))
            sanitized = "***-**-\(last4)"
        }

        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
        lastChangeCount = pasteboard.changeCount
        detectedSensitiveItem = nil
    }

    func encryptToVault() {
        guard let item = detectedSensitiveItem else { return }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("Clipboard_\(item.kind.rawValue.replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString.prefix(6)).txt")
        try? item.rawText.write(to: tempFile, atomically: true, encoding: .utf8)

        Task {
            try? await PalVaultService.shared.importFile(from: tempFile, deleteSource: true)
            self.sanitizeClipboard()
        }
    }

    func dismiss() {
        detectedSensitiveItem = nil
    }

    // MARK: - Pattern Analysis

    private func analyzeTextForSecrets(_ text: String) -> ClipboardSensitiveItem? {
        // 1. OpenAI Keys
        if let match = firstRegexMatch(pattern: #"\bsk-[a-zA-Z0-9]{20,}\b"#, in: text) {
            return ClipboardSensitiveItem(id: UUID().uuidString, kind: .openAIKey, snippet: maskSnippet(match), rawText: text)
        }

        // 2. Anthropic Keys
        if let match = firstRegexMatch(pattern: #"\bsk-ant-[a-zA-Z0-9\-]{20,}\b"#, in: text) {
            return ClipboardSensitiveItem(id: UUID().uuidString, kind: .anthropicKey, snippet: maskSnippet(match), rawText: text)
        }

        // 3. AWS Keys
        if let match = firstRegexMatch(pattern: #"\bAKIA[0-9A-Z]{16}\b"#, in: text) {
            return ClipboardSensitiveItem(id: UUID().uuidString, kind: .awsKey, snippet: maskSnippet(match), rawText: text)
        }

        // 4. GitHub Tokens
        if let match = firstRegexMatch(pattern: #"\bghp_[a-zA-Z0-9]{36}\b"#, in: text) {
            return ClipboardSensitiveItem(id: UUID().uuidString, kind: .githubToken, snippet: maskSnippet(match), rawText: text)
        }

        // 5. Private Keys
        if text.contains("-----BEGIN") && text.contains("PRIVATE KEY-----") {
            return ClipboardSensitiveItem(id: UUID().uuidString, kind: .privateKey, snippet: "-----BEGIN PRIVATE KEY-----", rawText: text)
        }

        // 6. Social Security Numbers
        if let match = firstRegexMatch(pattern: #"\b\d{3}-\d{2}-\d{4}\b"#, in: text) {
            return ClipboardSensitiveItem(id: UUID().uuidString, kind: .ssn, snippet: match, rawText: text)
        }

        // 7. Credit Cards
        if let match = firstRegexMatch(pattern: #"\b(?:\d[ -]*?){13,16}\b"#, in: text) {
            let digits = match.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)
            if digits.count >= 13 && digits.count <= 19 && passesLuhn(digits) {
                return ClipboardSensitiveItem(id: UUID().uuidString, kind: .creditCard, snippet: match, rawText: text)
            }
        }

        return nil
    }

    private func firstRegexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private func maskSnippet(_ raw: String) -> String {
        guard raw.count > 8 else { return "********" }
        let prefix = raw.prefix(4)
        let suffix = raw.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func passesLuhn(_ number: String) -> Bool {
        var sum = 0
        let reversed = number.reversed().map { Int(String($0)) ?? 0 }
        for (idx, digit) in reversed.enumerated() {
            if idx % 2 == 1 {
                let doubled = digit * 2
                sum += (doubled > 9 ? doubled - 9 : doubled)
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
