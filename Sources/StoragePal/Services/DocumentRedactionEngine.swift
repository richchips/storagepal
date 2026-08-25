import AppKit
import CoreGraphics
import Foundation
import NaturalLanguage
import PDFKit

actor DocumentRedactionEngine {
    private let fm = FileManager.default

    // Stop words to prevent common medical/clinical terms from triggering false-positive IDs
    private let stopWords: Set<String> = [
        "record", "records", "assessment", "assessments", "clinical", "note", "notes",
        "history", "training", "material", "summary", "report", "intake", "discharge",
        "appointment", "session", "review", "evaluation", "formulation", "client", "patient"
    ]

    init() {}

    // MARK: - Document Scanning

    func scanDocument(
        at url: URL,
        template: RedactionTemplateKind,
        policy: PrivacyPolicyTier = .internalClinical,
        customKeywords: [String] = [],
        customRegex: String? = nil
    ) -> (matches: [SensitiveEntityMatch], textContent: String) {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return ([], "") }
            var fullText = ""
            var allMatches: [SensitiveEntityMatch] = []
            var sharedEntityTokenMap: [String: String] = [:]
            var tokenCounters: [String: Int] = [:]

            for pageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: pageIndex), let pageString = page.string else { continue }
                fullText += "--- Page \(pageIndex + 1) ---\n" + pageString + "\n\n"
                let pageMatches = scanText(
                    text: pageString,
                    template: template,
                    policy: policy,
                    pageIndex: pageIndex + 1,
                    customKeywords: customKeywords,
                    customRegex: customRegex,
                    sharedEntityTokenMap: &sharedEntityTokenMap,
                    tokenCounters: &tokenCounters
                )
                allMatches.append(contentsOf: pageMatches)
            }
            return (allMatches, fullText)
        } else {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            var sharedEntityTokenMap: [String: String] = [:]
            var tokenCounters: [String: Int] = [:]
            let matches = scanText(
                text: text,
                template: template,
                policy: policy,
                pageIndex: 1,
                customKeywords: customKeywords,
                customRegex: customRegex,
                sharedEntityTokenMap: &sharedEntityTokenMap,
                tokenCounters: &tokenCounters
            )
            return (matches, text)
        }
    }

    // MARK: - Core Pattern Matching & NER

    func scanText(
        text: String,
        template: RedactionTemplateKind,
        policy: PrivacyPolicyTier = .internalClinical,
        pageIndex: Int = 1,
        customKeywords: [String] = [],
        customRegex: String? = nil,
        sharedEntityTokenMap: inout [String: String],
        tokenCounters: inout [String: Int]
    ) -> [SensitiveEntityMatch] {
        var matches: [SensitiveEntityMatch] = []

        func getOrMakeToken(for rawText: String, prefix: String) -> String {
            let key = rawText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let existing = sharedEntityTokenMap[key] {
                return existing
            }
            let count = (tokenCounters[prefix] ?? 0) + 1
            tokenCounters[prefix] = count
            let token = "[\(prefix)_\(count)]"
            sharedEntityTokenMap[key] = token
            return token
        }

        // Idempotency: Find existing bracketed tokens to skip them
        let existingTokens = findExistingBracketedTokens(in: text)

        switch template {
        case .clinicalPsychology, .medical:
            // Tier 1: Direct Names (Header patterns, titles, and ML Named Entity Recognition)
            matches.append(contentsOf: findClientAndPatientNames(in: text, pageIndex: pageIndex, tokenProvider: { getOrMakeToken(for: $0, prefix: "PERSON") }))
            matches.append(contentsOf: findHonorificNames(in: text, pageIndex: pageIndex, tokenProvider: { getOrMakeToken(for: $0, prefix: "PERSON") }))
            matches.append(contentsOf: findNLNamedEntities(in: text, pageIndex: pageIndex, tokenProvider: { getOrMakeToken(for: $0, prefix: "PERSON") }))

            // Tier 1: Genuine Patient Identifiers (NHS / MRN / Hospital IDs requiring digits)
            matches.append(contentsOf: findPatientIdentifiers(in: text, pageIndex: pageIndex, tokenProvider: { getOrMakeToken(for: $0, prefix: "PATIENT_ID") }))

            // Tier 1: Contact details & addresses
            matches.append(contentsOf: findContactDetails(in: text, pageIndex: pageIndex, getOrMakeToken: getOrMakeToken))

            // Tier 2: Quasi-Identifiers (Dates & Ages)
            let isStrict = (policy == .externalResearch)
            matches.append(contentsOf: findQuasiDates(in: text, pageIndex: pageIndex, isStrict: isStrict, tokenProvider: { getOrMakeToken(for: $0, prefix: "DATE") }))
            matches.append(contentsOf: findQuasiAges(in: text, pageIndex: pageIndex, isStrict: isStrict, tokenProvider: { getOrMakeToken(for: $0, prefix: "AGE") }))

        case .financial:
            // SSN & UK NI
            matches.append(contentsOf: findRegexMatches(pattern: #"\b\d{3}-\d{2}-\d{4}\b"#, in: text, category: "SSN / Tax ID", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "SSN") })
            matches.append(contentsOf: findRegexMatches(pattern: #"\b[A-CEGHJ-PR-TW-Z]{2}\s?\d{6}\s?[A-D]\b"#, in: text, category: "National Insurance", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "TAX_ID") })
            // Credit Cards (Luhn validated)
            matches.append(contentsOf: findCreditCardMatches(in: text, pageIndex: pageIndex) { getOrMakeToken(for: $0, prefix: "CARD") })
            // IBAN / Bank Accounts
            matches.append(contentsOf: findRegexMatches(pattern: #"\b[A-Z]{2}\d{2}[A-Z0-9]{4}\d{7}([A-Z0-9]?){0,16}\b"#, in: text, category: "Bank Account / IBAN", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "BANK_ACCOUNT") })
            // Monetary Amounts
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:\$|£|€)\s?[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?|\b[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?\s?(?:USD|EUR|GBP|CAD|AUD)\b"#, in: text, category: "Financial Sum", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "AMOUNT") })

        case .legal:
            // Client / Party names
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:Party|Client|Borrower|Lender|Assignor|Assignee|Licensor|Licensee)\s*[:\-]?\s*([A-Z][a-zA-Z\s,]+)"#, in: text, category: "Legal Party", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "PARTY") })
            matches.append(contentsOf: findRegexMatches(pattern: #"\b(?:Case|Matter|Docket|Claim)\s*(?:No\.?|#)?\s*[:\s]*([A-Z0-9\-]{4,20})\b"#, in: text, category: "Case Number", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "CASE_ID") })
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:\$|£|€)\s?[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?"#, in: text, category: "Settlement Amount", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "SETTLEMENT") })

        case .hr:
            matches.append(contentsOf: findContactDetails(in: text, pageIndex: pageIndex, getOrMakeToken: getOrMakeToken))
            matches.append(contentsOf: findRegexMatches(pattern: #"(?:\$|£|€)\s?[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?|\b[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?\s?(?:k|K|/yr|/year|per year)\b"#, in: text, category: "Salary History", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "SALARY") })

        case .custom:
            for keyword in customKeywords where !keyword.trimmingCharacters(in: .whitespaces).isEmpty {
                let escaped = NSRegularExpression.escapedPattern(for: keyword)
                matches.append(contentsOf: findRegexMatches(pattern: "\\b\(escaped)\\b", in: text, category: "Custom Keyword", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "CUSTOM") })
            }
            if let customRegex = customRegex, !customRegex.isEmpty {
                matches.append(contentsOf: findRegexMatches(pattern: customRegex, in: text, category: "Custom Regex", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken(for: $0, prefix: "MATCH") })
            }
        }

        // Filter out already tokenized placeholders (Idempotency)
        let filteredMatches = matches.filter { match in
            !existingTokens.contains(match.originalText) && !stopWords.contains(match.originalText.lowercased())
        }

        // Deduplicate overlapping matches by range/text
        var unique: [SensitiveEntityMatch] = []
        var seenTexts: Set<String> = []
        for m in filteredMatches {
            let key = "\(m.pageIndex):\(m.originalText)"
            if !seenTexts.contains(key) {
                seenTexts.insert(key)
                unique.append(m)
            }
        }

        return unique
    }

    // MARK: - Specialized Detection Routines

    private func findClientAndPatientNames(in text: String, pageIndex: Int, tokenProvider: (String) -> String) -> [SensitiveEntityMatch] {
        var results: [SensitiveEntityMatch] = []

        // 1. "Client: Sam R." or "Client Sam R." or "Patient: John Doe"
        let headerPattern = #"\b(?:Client|Patient|Assessor|Therapist|Counselor|Doctor)\s*[:\-]?\s+([A-Z][a-z]+(?:\s+[A-Z]\.?|\s+[A-Z][a-z]+))\b"#
        if let regex = try? NSRegularExpression(pattern: headerPattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                    let nameStr = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !stopWords.contains(nameStr.lowercased()) else { continue }
                    results.append(
                        SensitiveEntityMatch(
                            category: "Client / Patient Name",
                            originalText: nameStr,
                            tokenReplacement: tokenProvider(nameStr),
                            pageIndex: pageIndex,
                            isEnabled: true,
                            tier: .directIdentifier
                        )
                    )
                }
            }
        }

        // 2. Initials/Short names: e.g. "Sam R."
        let initialPattern = #"\b([A-Z][a-z]{1,20}\s+[A-Z]\.)\b"#
        if let regex = try? NSRegularExpression(pattern: initialPattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                let nameStr = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !stopWords.contains(nameStr.lowercased()) else { continue }
                results.append(
                    SensitiveEntityMatch(
                        category: "Person Name",
                        originalText: nameStr,
                        tokenReplacement: tokenProvider(nameStr),
                        pageIndex: pageIndex,
                        isEnabled: true,
                        tier: .directIdentifier
                    )
                )
            }
        }

        return results
    }

    private func findHonorificNames(in text: String, pageIndex: Int, tokenProvider: (String) -> String) -> [SensitiveEntityMatch] {
        var results: [SensitiveEntityMatch] = []
        let pattern = #"\b(?:Dr|Mr|Mrs|Ms|Miss|Prof|Doctor)\.?\s+([A-Z][a-z]+(?:\s+[A-Z]\.?|\s+[A-Z][a-z]+)?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                let fullMatch = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !stopWords.contains(fullMatch.lowercased()) else { continue }
                results.append(
                    SensitiveEntityMatch(
                        category: "Practitioner / Person Name",
                        originalText: fullMatch,
                        tokenReplacement: tokenProvider(fullMatch),
                        pageIndex: pageIndex,
                        isEnabled: true,
                        tier: .directIdentifier
                    )
                )
            }
        }
        return results
    }

    private func findNLNamedEntities(in text: String, pageIndex: Int, tokenProvider: (String) -> String) -> [SensitiveEntityMatch] {
        var results: [SensitiveEntityMatch] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName {
                let nameStr = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if nameStr.count >= 3 && !stopWords.contains(nameStr.lowercased()) && !nameStr.contains("\n") {
                    results.append(
                        SensitiveEntityMatch(
                            category: "Named Person",
                            originalText: nameStr,
                            tokenReplacement: tokenProvider(nameStr),
                            pageIndex: pageIndex,
                            isEnabled: true,
                            tier: .directIdentifier
                        )
                    )
                }
            }
            return true
        }
        return results
    }

    private func findPatientIdentifiers(in text: String, pageIndex: Int, tokenProvider: (String) -> String) -> [SensitiveEntityMatch] {
        var results: [SensitiveEntityMatch] = []

        // 1. NHS Number: 10 digits formatted e.g. "987 654 3210" or "9876543210"
        let nhsPattern = #"\b\d{3}\s?\d{3}\s?\d{4}\b"#
        if let regex = try? NSRegularExpression(pattern: nhsPattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                let digits = String(text[range])
                results.append(
                    SensitiveEntityMatch(
                        category: "NHS Number",
                        originalText: digits,
                        tokenReplacement: tokenProvider(digits),
                        pageIndex: pageIndex,
                        isEnabled: true,
                        tier: .directIdentifier
                    )
                )
            }
        }

        // 2. Structured MRN / Hospital Number: must have alphanumeric ID containing >= 2 digits
        let mrnPattern = #"\b(?:MRN|Patient ID|Hospital ID|Chart ID)\s*[:#\-\s]\s*([A-Z0-9\-]{4,14})\b"#
        if let regex = try? NSRegularExpression(pattern: mrnPattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                    let idCandidate = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let digitCount = idCandidate.filter { $0.isNumber }.count
                    // Must contain at least 2 digits to prevent common words
                    guard digitCount >= 2 && !stopWords.contains(idCandidate.lowercased()) else { continue }
                    results.append(
                        SensitiveEntityMatch(
                            category: "Patient / Medical ID",
                            originalText: idCandidate,
                            tokenReplacement: tokenProvider(idCandidate),
                            pageIndex: pageIndex,
                            isEnabled: true,
                            tier: .directIdentifier
                        )
                    )
                }
            }
        }

        return results
    }

    private func findContactDetails(
        in text: String,
        pageIndex: Int,
        getOrMakeToken: (String, String) -> String
    ) -> [SensitiveEntityMatch] {
        var results: [SensitiveEntityMatch] = []

        // Emails
        results.append(contentsOf: findRegexMatches(pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#, in: text, category: "Personal Email", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken($0, "EMAIL") })

        // Phones
        results.append(contentsOf: findRegexMatches(pattern: #"(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#, in: text, category: "Phone Number", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken($0, "PHONE") })

        // UK Postcodes
        results.append(contentsOf: findRegexMatches(pattern: #"\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b"#, in: text, category: "Postcode", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken($0, "POSTCODE") })

        // Street Addresses
        results.append(contentsOf: findRegexMatches(pattern: #"\b\d{1,5}\s+[A-Za-z0-9\.\s]{3,25}(?:Road|Rd|Street|St|Avenue|Ave|Lane|Ln|Drive|Dr|Way|Boulevard|Blvd|Court|Ct)\b"#, in: text, category: "Street Address", pageIndex: pageIndex, tier: .directIdentifier) { getOrMakeToken($0, "ADDRESS") })

        return results
    }

    private func findQuasiDates(in text: String, pageIndex: Int, isStrict: Bool, tokenProvider: (String) -> String) -> [SensitiveEntityMatch] {
        var results: [SensitiveEntityMatch] = []
        // Numeric dates: 25/08/2026, 2026-08-25, 25-08-2026
        let datePattern = #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#
        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                let dateStr = String(text[range])
                results.append(
                    SensitiveEntityMatch(
                        category: "Exact Date",
                        originalText: dateStr,
                        tokenReplacement: tokenProvider(dateStr),
                        pageIndex: pageIndex,
                        isEnabled: isStrict, // Enabled by default in Strict / External Research mode
                        tier: .quasiIdentifier
                    )
                )
            }
        }
        return results
    }

    private func findQuasiAges(in text: String, pageIndex: Int, isStrict: Bool, tokenProvider: (String) -> String) -> [SensitiveEntityMatch] {
        var results: [SensitiveEntityMatch] = []
        // "Age 36" or "Age: 36"
        let agePattern = #"\b(?:Age|Aged)\s*[:\s]*(\d{1,3})\b"#
        if let regex = try? NSRegularExpression(pattern: agePattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                    let ageStr = String(text[range])
                    results.append(
                        SensitiveEntityMatch(
                            category: "Exact Age",
                            originalText: ageStr,
                            tokenReplacement: tokenProvider(ageStr),
                            pageIndex: pageIndex,
                            isEnabled: isStrict,
                            tier: .quasiIdentifier
                        )
                    )
                }
            }
        }
        return results
    }

    private func findExistingBracketedTokens(in text: String) -> Set<String> {
        var set: Set<String> = []
        let pattern = #"\[[A-Z0-9_]{2,20}\]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if let range = Range(match.range, in: text) {
                    set.insert(String(text[range]))
                }
            }
        }
        return set
    }

    // MARK: - Redaction Transformations

    func redactText(originalText: String, matches: [SensitiveEntityMatch], mode: RedactionMode) -> String {
        var result = originalText
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
                    annotation.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)
                    annotation.fontColor = .black
                    annotation.color = NSColor(red: 0.88, green: 0.96, blue: 0.92, alpha: 1.0)
                    page.addAnnotation(annotation)
                }
            }
        }

        // Apply Manual Redaction Boxes
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

        // Structural Flattening: rasterize pages to prevent text layer extraction
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

        // Clean document attributes / metadata
        flattenedPDF.documentAttributes = [:]

        guard flattenedPDF.write(to: targetURL) else {
            throw NSError(domain: "DocumentRedactionEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write redacted PDF."])
        }
    }

    // MARK: - Generic Regex Helpers

    private func findRegexMatches(
        pattern: String,
        in text: String,
        category: String,
        pageIndex: Int,
        tier: SensitiveEntityTier,
        tokenGenerator: (String) -> String
    ) -> [SensitiveEntityMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let results = regex.matches(in: text, options: [], range: nsRange)

        var matches: [SensitiveEntityMatch] = []
        for match in results {
            guard let range = Range(match.range, in: text) else { continue }
            let substring = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !substring.isEmpty && !stopWords.contains(substring.lowercased()) else { continue }

            let token = tokenGenerator(substring)
            matches.append(
                SensitiveEntityMatch(
                    category: category,
                    originalText: substring,
                    tokenReplacement: token,
                    pageIndex: pageIndex,
                    isEnabled: true,
                    tier: tier
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

            guard digitsOnly.count >= 13 && digitsOnly.count <= 19 && passesLuhnCheck(digitsOnly) else { continue }

            let token = tokenGenerator(candidate)
            matches.append(
                SensitiveEntityMatch(
                    category: "Credit / Debit Card",
                    originalText: candidate,
                    tokenReplacement: token,
                    pageIndex: pageIndex,
                    isEnabled: true,
                    tier: .directIdentifier
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
