import CoreGraphics
import Foundation
import PDFKit

actor DocumentRedactionEngine {
    private let fm = FileManager.default

    init() {}

    // MARK: - Document Scanning

    func scanDocument(
        at url: URL,
        template: RedactionTemplateKind,
        customKeywords: [String] = [],
        customRegex: String? = nil
    ) -> (matches: [SensitiveEntityMatch], textContent: String) {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return ([], "") }
            var fullText = ""
            var allMatches: [SensitiveEntityMatch] = []

            for pageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: pageIndex), let pageString = page.string else { continue }
                fullText += "--- Page \(pageIndex + 1) ---\n" + pageString + "\n\n"
                let pageMatches = scanText(
                    text: pageString,
                    template: template,
                    pageIndex: pageIndex + 1,
                    customKeywords: customKeywords,
                    customRegex: customRegex
                )
                allMatches.append(contentsOf: pageMatches)
            }
            return (allMatches, fullText)
        } else {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let matches = scanText(
                text: text,
                template: template,
                pageIndex: 1,
                customKeywords: customKeywords,
                customRegex: customRegex
            )
            return (matches, text)
        }
    }

    // MARK: - Pattern Matching

    func scanText(
        text: String,
        template: RedactionTemplateKind,
        pageIndex: Int = 1,
        customKeywords: [String] = [],
        customRegex: String? = nil
    ) -> [SensitiveEntityMatch] {
        var matches: [SensitiveEntityMatch] = []
        var tokenCounters: [String: Int] = [:]

        func nextToken(for prefix: String) -> String {
            let count = (tokenCounters[prefix] ?? 0) + 1
            tokenCounters[prefix] = count
            return "[\(prefix)_\(count)]"
        }

        switch template {
        case .financial:
            // SSN
            matches.append(contentsOf: findRegexMatches(pattern: #"\b\d{3}-\d{2}-\d{4}\b"#, in: text, category: "SSN / Tax ID", pageIndex: pageIndex) { _ in nextToken(for: "SSN") })
            // UK NI
            matches.append(contentsOf: findRegexMatches(pattern: #"\b[A-CEGHJ-PR-TW-Z]{2}\s?\d{6}\s?[A-D]\b"#, in: text, category: "National Insurance", pageIndex: pageIndex) { _ in nextToken(for: "TAX_ID") })
            // Credit Cards (13-16 digits with Luhn)
            matches.append(contentsOf: findCreditCardMatches(in: text, pageIndex: pageIndex) { _ in nextToken(for: "CARD") })
            // IBAN / Bank Accounts
            matches.append(contentsOf: findRegexMatches(pattern: #"\b[A-Z]{2}\d{2}[A-Z0-9]{4}\d{7}([A-Z0-9]?){0,16}\b"#, in: text, category: "Bank Account / IBAN", pageIndex: pageIndex) { _ in nextToken(for: "BANK_ACCOUNT") })
            // Monetary Amounts
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:\$|£|€)\s?[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?|\b[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?\s?(?:USD|EUR|GBP|CAD|AUD)\b"#, in: text, category: "Financial Sum", pageIndex: pageIndex) { _ in nextToken(for: "AMOUNT") })

        case .legal:
            // Client / Party names
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:Party|Client|Borrower|Lender|Assignor|Assignee|Licensor|Licensee):\s*([A-Z][a-zA-Z\s,]+)"#, in: text, category: "Legal Party", pageIndex: pageIndex) { _ in nextToken(for: "PARTY") })
            // Case / Docket numbers
            matches.append(contentsOf: findRegexMatches(pattern: #"\b(?:Case|Matter|Docket|Claim)\s*(?:No\.?|#)?\s*[:\s]*[A-Z0-9\-]+\b"#, in: text, category: "Case Number", pageIndex: pageIndex) { _ in nextToken(for: "CASE_ID") })
            // Monetary Settlement Figures
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:\$|£|€)\s?[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?"#, in: text, category: "Settlement Amount", pageIndex: pageIndex) { _ in nextToken(for: "SETTLEMENT") })

        case .medical:
            // Patient MRN / NHS
            matches.append(contentsOf: findRegexMatches(pattern: #"\b(?:MRN|NHS|Patient ID|Chart|Record)\s*(?:No\.?|#)?\s*[:\s]*[A-Z0-9\-]{4,12}\b"#, in: text, category: "Patient Identifier", pageIndex: pageIndex) { _ in nextToken(for: "PATIENT_ID") })
            // Dates of Birth
            matches.append(contentsOf: findRegexMatches(pattern: #"\b(?:DOB|Date of Birth|Born):\s*\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#, in: text, category: "Date of Birth", pageIndex: pageIndex) { _ in nextToken(for: "DOB") })
            // Prescription / Dosage
            matches.append(contentsOf: findRegexMatches(pattern: #"\b\d+(?:\.\d+)?\s*(?:mg|mcg|ml|tablets|capsules|units)\b"#, in: text, category: "Prescription Dosage", pageIndex: pageIndex) { _ in nextToken(for: "DOSAGE") })

        case .hr:
            // Emails
            matches.append(contentsOf: findRegexMatches(pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#, in: text, category: "Personal Email", pageIndex: pageIndex) { _ in nextToken(for: "EMAIL") })
            // Phone numbers
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#, in: text, category: "Phone Number", pageIndex: pageIndex) { _ in nextToken(for: "PHONE") })
            // Salary Figures
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:\$|£|€)\s?[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?|\b[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?\s?(?:k|K|/yr|/year|per year)\b"#, in: text, category: "Salary History", pageIndex: pageIndex) { _ in nextToken(for: "SALARY") })

        case .custom:
            // Custom keywords
            for keyword in customKeywords where !keyword.trimmingCharacters(in: .whitespaces).isEmpty {
                let escaped = NSRegularExpression.escapedPattern(for: keyword)
                matches.append(contentsOf: findRegexMatches(pattern: "\\b\(escaped)\\b", in: text, category: "Custom Keyword", pageIndex: pageIndex) { _ in nextToken(for: "CUSTOM") })
            }
            // Custom regex
            if let customRegex = customRegex, !customRegex.isEmpty {
                matches.append(contentsOf: findRegexMatches(pattern: customRegex, in: text, category: "Custom Regex", pageIndex: pageIndex) { _ in nextToken(for: "MATCH") })
            }
        }

        // Deduplicate overlapping matches
        var unique: [SensitiveEntityMatch] = []
        var seenTexts: Set<String> = []
        for m in matches {
            let key = "\(m.pageIndex):\(m.originalText)"
            if !seenTexts.contains(key) {
                seenTexts.insert(key)
                unique.append(m)
            }
        }

        return unique
    }

    // MARK: - Redaction Transformations

    func redactText(originalText: String, matches: [SensitiveEntityMatch], mode: RedactionMode) -> String {
        var result = originalText
        // Sort by length descending to replace longer matches first (e.g. "$500,000" before "$500")
        let enabledMatches = matches.filter { $0.isEnabled }.sorted { $0.originalText.count > $1.originalText.count }

        for match in enabledMatches {
            let replacement: String
            switch mode {
            case .aiTokenSwap:
                replacement = match.tokenReplacement
            case .blackout:
                replacement = String(repeating: "█", count: max(4, match.originalText.count))
            case .redactedLabel:
                replacement = "[REDACTED: \(match.category.uppercased())]"
            }
            result = result.replacingOccurrences(of: match.originalText, with: replacement)
        }
        return result
    }

    func generateAIPrompt(role: AIPromptRolePreset, documentName: String, tokenizedText: String) -> String {
        """
        \(role.systemPreamble)

        --- DOCUMENT BEGIN: \(documentName) ---
        \(tokenizedText)
        --- DOCUMENT END ---
        """
    }

    func redactPDF(
        sourceURL: URL,
        matches: [SensitiveEntityMatch],
        manualBoxes: [ManualRedactionBox] = [],
        mode: RedactionMode,
        targetURL: URL
    ) throws {
        guard let pdf = PDFDocument(url: sourceURL) else {
            throw NSError(domain: "DocumentRedactionEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document."])
        }

        let enabledMatches = matches.filter { $0.isEnabled }

        // Process PDF pages: find occurrences and burn solid blackouts or text replacement
        for match in enabledMatches {
            let selections = pdf.findString(match.originalText, withOptions: .caseInsensitive)
            for selection in selections {
                guard let page = selection.pages.first else { continue }
                let bounds = selection.bounds(for: page)

                switch mode {
                case .blackout:
                    let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
                    annotation.color = .black
                    annotation.interiorColor = .black
                    page.addAnnotation(annotation)
                case .redactedLabel, .aiTokenSwap:
                    let label = mode == .aiTokenSwap ? match.tokenReplacement : "[REDACTED]"
                    let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
                    annotation.contents = label
                    annotation.font = NSFont.systemFont(ofSize: 8, weight: .bold)
                    annotation.fontColor = .white
                    annotation.color = .black
                    page.addAnnotation(annotation)
                }
            }
        }

        // Apply Manual Redaction Boxes (visual custom blackout regions)
        for box in manualBoxes {
            let pageIdx = max(0, min(box.pageIndex - 1, pdf.pageCount - 1))
            guard let page = pdf.page(at: pageIdx), box.rectNormalized.count == 4 else { continue }
            let pageBounds = page.bounds(for: .mediaBox)

            let x = box.rectNormalized[0] * pageBounds.width
            let y = (1.0 - box.rectNormalized[1] - box.rectNormalized[3]) * pageBounds.height
            let w = box.rectNormalized[2] * pageBounds.width
            let h = box.rectNormalized[3] * pageBounds.height

            let manualBounds = CGRect(x: x, y: y, width: w, height: h)
            let annotation = PDFAnnotation(bounds: manualBounds, forType: .square, withProperties: nil)
            annotation.color = .black
            annotation.interiorColor = .black
            page.addAnnotation(annotation)
        }

        // True Structural Flattening: rasterize pages to prevent text extraction from behind annotations
        let flattenedPDF = PDFDocument()
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0 // Crisp 144 DPI
            let pixelSize = CGSize(width: max(100, pageBounds.width * scale), height: max(100, pageBounds.height * scale))

            let image = page.thumbnail(of: pixelSize, for: .mediaBox)
            if let pageFromImage = PDFPage(image: image) {
                flattenedPDF.insert(pageFromImage, at: flattenedPDF.pageCount)
            } else {
                flattenedPDF.insert(page, at: flattenedPDF.pageCount)
            }
        }

        // Clean document attributes
        flattenedPDF.documentAttributes = [:]

        guard flattenedPDF.write(to: targetURL) else {
            throw NSError(domain: "DocumentRedactionEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write redacted PDF."])
        }
    }

    // MARK: - Regex Helpers

    private func findRegexMatches(
        pattern: String,
        in text: String,
        category: String,
        pageIndex: Int,
        tokenGenerator: (String) -> String
    ) -> [SensitiveEntityMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let results = regex.matches(in: text, options: [], range: nsRange)

        var matches: [SensitiveEntityMatch] = []
        for match in results {
            guard let range = Range(match.range, in: text) else { continue }
            let substring = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !substring.isEmpty else { continue }

            let token = tokenGenerator(substring)
            matches.append(
                SensitiveEntityMatch(
                    id: UUID().uuidString,
                    category: category,
                    originalText: substring,
                    tokenReplacement: token,
                    pageIndex: pageIndex,
                    isEnabled: true
                )
            )
        }
        return matches
    }

    private func findCreditCardMatches(in text: String, pageIndex: Int, tokenGenerator: (String) -> String) -> [SensitiveEntityMatch] {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,16}\b"#) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let results = regex.matches(in: text, options: [], range: nsRange)

        var matches: [SensitiveEntityMatch] = []
        for match in results {
            guard let range = Range(match.range, in: text) else { continue }
            let candidate = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let digitsOnly = candidate.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)

            // Validate card length & Luhn algorithm
            guard digitsOnly.count >= 13 && digitsOnly.count <= 19 && passesLuhnCheck(digitsOnly) else { continue }

            let token = tokenGenerator(candidate)
            matches.append(
                SensitiveEntityMatch(
                    id: UUID().uuidString,
                    category: "Credit / Debit Card",
                    originalText: candidate,
                    tokenReplacement: token,
                    pageIndex: pageIndex,
                    isEnabled: true
                )
            )
        }
        return matches
    }

    private func passesLuhnCheck(_ number: String) -> Bool {
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
