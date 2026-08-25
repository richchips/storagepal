import Foundation
import PDFKit
import UniformTypeIdentifiers

actor AIWatermarkSanitizerService {
    static let shared = AIWatermarkSanitizerService()

    private let fm = FileManager.default

    init() {}

    // MARK: - Core Analysis & Sanitization

    func analyzeAndSanitize(
        text: String,
        sourceName: String = "Pasted Text",
        options: AIWatermarkCleaningOptions = AIWatermarkCleaningOptions()
    ) -> AIWatermarkReport {
        guard !text.isEmpty else {
            return AIWatermarkReport.empty
        }

        var workingText = text
        var findings: [AIWatermarkFinding] = []
        var visualMarkerText = ""
        var invisibleCount = 0
        var homoglyphCount = 0
        var aiSignatureCount = 0

        // Step 1: Detect and strip invisible Unicode & Steganographic Zero-Width Markers
        if options.stripInvisibleUnicode {
            let (strippedText, visualText, invCount, invFindings) = detectAndStripInvisibleUnicode(from: workingText)
            workingText = strippedText
            visualMarkerText = visualText
            invisibleCount = invCount
            findings.append(contentsOf: invFindings)
        } else {
            visualMarkerText = workingText
        }

        // Step 2: Detect and normalize Homoglyph / Confusable Lookalikes
        if options.normalizeHomoglyphs {
            let (normalizedText, hCount, hFindings) = detectAndNormalizeHomoglyphs(from: workingText)
            workingText = normalizedText
            homoglyphCount = hCount
            findings.append(contentsOf: hFindings)
        }

        // Step 3: Strip AI conversational wrappers / preambles / disclaimers
        if options.stripAIPromptArtifacts {
            let (cleanedText, aiCount, aiFindings) = detectAndStripAIChatbotArtifacts(from: workingText)
            workingText = cleanedText
            aiSignatureCount = aiCount
            findings.append(contentsOf: aiFindings)
        }

        // Step 4: Optional Whitespace and Canonical Cleanup
        if options.normalizeWhitespace {
            workingText = normalizeWhitespaceAndNFKC(workingText)
        }

        let totalFound = invisibleCount + homoglyphCount + aiSignatureCount
        let confidence: Int
        if invisibleCount > 0 || homoglyphCount > 0 {
            confidence = min(100, 40 + (invisibleCount * 10) + (homoglyphCount * 15) + (aiSignatureCount * 20))
        } else if aiSignatureCount > 0 {
            confidence = 65
        } else {
            confidence = 0
        }

        return AIWatermarkReport(
            sourceName: sourceName,
            totalWatermarksFound: totalFound,
            invisibleCharactersCount: invisibleCount,
            homoglyphsCount: homoglyphCount,
            aiSignaturesCount: aiSignatureCount,
            purifiedText: workingText,
            rawWithVisualMarkers: visualMarkerText,
            findings: findings,
            steganographyConfidencePercent: confidence
        )
    }

    // MARK: - File Sanitization

    func sanitizeFile(
        at sourceURL: URL,
        destinationDirectory: URL,
        options: AIWatermarkCleaningOptions = AIWatermarkCleaningOptions()
    ) throws -> (targetURL: URL, report: AIWatermarkReport) {
        let ext = sourceURL.pathExtension.lowercased()
        let cleanFileName = "\(sourceURL.deletingPathExtension().lastPathComponent)_ai_purified.\(ext)"
        let targetURL = destinationDirectory.appendingPathComponent(cleanFileName)

        if ext == "pdf" {
            return try sanitizePDF(sourceURL: sourceURL, targetURL: targetURL, options: options)
        } else {
            // Text, Markdown, CSV, Source Code, RTF
            let rawContent = try String(contentsOf: sourceURL, encoding: .utf8)
            let report = analyzeAndSanitize(text: rawContent, sourceName: sourceURL.lastPathComponent, options: options)
            try report.purifiedText.write(to: targetURL, atomically: true, encoding: .utf8)
            return (targetURL, report)
        }
    }

    // MARK: - Private Invisible Unicode Steganography Handler

    private func detectAndStripInvisibleUnicode(from text: String) -> (String, String, Int, [AIWatermarkFinding]) {
        var cleanScalars: [UnicodeScalar] = []
        var visualScalars: [UnicodeScalar] = []
        var invisibleCount = 0
        var categoryCounts: [String: (count: Int, kind: AIWatermarkKind)] = [:]

        for scalar in text.unicodeScalars {
            let val = scalar.value

            // Zero-Width Space & Markers
            if val == 0x200B { // Zero-Width Space
                invisibleCount += 1
                recordCategory("Zero-Width Space (U+200B)", kind: .zeroWidthSteganography, counts: &categoryCounts)
                appendVisualBadge("[ZW-SPACE]", to: &visualScalars)
            } else if val == 0x200C { // Zero-Width Non-Joiner
                invisibleCount += 1
                recordCategory("Zero-Width Non-Joiner (U+200C)", kind: .zeroWidthSteganography, counts: &categoryCounts)
                appendVisualBadge("[ZW-NJ]", to: &visualScalars)
            } else if val == 0x200D { // Zero-Width Joiner
                invisibleCount += 1
                recordCategory("Zero-Width Joiner (U+200D)", kind: .zeroWidthSteganography, counts: &categoryCounts)
                appendVisualBadge("[ZW-JOINER]", to: &visualScalars)
            } else if val == 0xFEFF { // Zero-Width No-Break Space / BOM
                invisibleCount += 1
                recordCategory("Zero-Width No-Break / BOM (U+FEFF)", kind: .zeroWidthSteganography, counts: &categoryCounts)
                appendVisualBadge("[ZW-BOM]", to: &visualScalars)
            } else if val == 0x2060 { // Word Joiner
                invisibleCount += 1
                recordCategory("Word Joiner (U+2060)", kind: .zeroWidthSteganography, counts: &categoryCounts)
                appendVisualBadge("[WORD-JOINER]", to: &visualScalars)
            } else if val == 0x00AD { // Soft Hyphen
                invisibleCount += 1
                recordCategory("Soft Hyphen (U+00AD)", kind: .zeroWidthSteganography, counts: &categoryCounts)
                appendVisualBadge("[SOFT-HYPHEN]", to: &visualScalars)
            } else if val == 0x180E { // Mongolian Vowel Separator
                invisibleCount += 1
                recordCategory("Mongolian Vowel Separator (U+180E)", kind: .zeroWidthSteganography, counts: &categoryCounts)
                appendVisualBadge("[MVS]", to: &visualScalars)
            }
            // Variation Selectors (U+FE00 to U+FE0F, U+E0100 to U+E01EF)
            else if (val >= 0xFE00 && val <= 0xFE0F) || (val >= 0xE0100 && val <= 0xE01EF) {
                invisibleCount += 1
                recordCategory("Variation Selector (\(String(format: "U+%04X", val)))", kind: .variationSelector, counts: &categoryCounts)
                appendVisualBadge("[VS-TAG]", to: &visualScalars)
            }
            // BiDi & Directional Formatting Controls (U+200E, U+200F, U+202A-U+202E, U+2066-U+2069)
            else if val == 0x200E || val == 0x200F || (val >= 0x202A && val <= 0x202E) || (val >= 0x2066 && val <= 0x2069) {
                invisibleCount += 1
                recordCategory("BiDi Directional Control (\(String(format: "U+%04X", val)))", kind: .bidiControl, counts: &categoryCounts)
                appendVisualBadge("[BIDI-CTRL]", to: &visualScalars)
            } else {
                cleanScalars.append(scalar)
                visualScalars.append(scalar)
            }
        }

        var cleanString = ""
        cleanString.unicodeScalars.append(contentsOf: cleanScalars)

        var visualString = ""
        visualString.unicodeScalars.append(contentsOf: visualScalars)

        var findings: [AIWatermarkFinding] = []
        for (desc, info) in categoryCounts {
            findings.append(
                AIWatermarkFinding(
                    kind: info.kind,
                    description: desc,
                    rawSample: info.kind.shortTag,
                    cleanedReplacement: "[Removed]",
                    locationOffset: 0,
                    occurrenceCount: info.count
                )
            )
        }

        return (cleanString, visualString, invisibleCount, findings)
    }

    private func recordCategory(_ desc: String, kind: AIWatermarkKind, counts: inout [String: (count: Int, kind: AIWatermarkKind)]) {
        if let existing = counts[desc] {
            counts[desc] = (existing.count + 1, kind)
        } else {
            counts[desc] = (1, kind)
        }
    }

    private func appendVisualBadge(_ badge: String, to scalars: inout [UnicodeScalar]) {
        for s in badge.unicodeScalars {
            scalars.append(s)
        }
    }

    // MARK: - Homoglyph / Lookalike Substitution Normalizer

    private func detectAndNormalizeHomoglyphs(from text: String) -> (String, Int, [AIWatermarkFinding]) {
        // Cyrillic & Greek lookalikes swapped into Latin text
        let homoglyphMap: [Character: Character] = [
            // Lowercase Cyrillic
            "\u{0430}": "a", // Cyrillic 'а'
            "\u{0435}": "e", // Cyrillic 'е'
            "\u{043E}": "o", // Cyrillic 'о'
            "\u{0440}": "p", // Cyrillic 'р'
            "\u{0441}": "s", // Cyrillic 'с'
            "\u{0443}": "y", // Cyrillic 'у'
            "\u{0445}": "x", // Cyrillic 'х'
            "\u{0456}": "i", // Cyrillic 'і'
            "\u{0458}": "j", // Cyrillic 'ј'
            // Uppercase Cyrillic
            "\u{0410}": "A",
            "\u{0412}": "B",
            "\u{0415}": "E",
            "\u{041A}": "K",
            "\u{041C}": "M",
            "\u{041D}": "H",
            "\u{041E}": "O",
            "\u{0420}": "P",
            "\u{0421}": "C",
            "\u{0422}": "T",
            "\u{0425}": "X",
            // Greek
            "\u{0391}": "A", "\u{0392}": "B", "\u{0395}": "E", "\u{0396}": "Z",
            "\u{0397}": "H", "\u{0399}": "I", "\u{039A}": "K", "\u{039C}": "M",
            "\u{039D}": "N", "\u{039F}": "O", "\u{03A1}": "P", "\u{03A4}": "T",
            "\u{03A5}": "Y", "\u{03A7}": "X", "\u{03BF}": "o", "\u{03BD}": "v", "\u{03C1}": "p"
        ]

        var count = 0
        var replacedText = ""
        replacedText.reserveCapacity(text.count)

        for char in text {
            if let standard = homoglyphMap[char] {
                count += 1
                replacedText.append(standard)
            } else {
                replacedText.append(char)
            }
        }

        var findings: [AIWatermarkFinding] = []
        if count > 0 {
            findings.append(
                AIWatermarkFinding(
                    kind: .homoglyphLookalike,
                    description: "Confusable Cyrillic/Greek character substitutions normalized to ASCII",
                    rawSample: "Lookalikes",
                    cleanedReplacement: "Standard Latin",
                    locationOffset: 0,
                    occurrenceCount: count
                )
            )
        }

        return (replacedText, count, findings)
    }

    // MARK: - AI Chatbot Preambles and Postambles Stripper

    private func detectAndStripAIChatbotArtifacts(from text: String) -> (String, Int, [AIWatermarkFinding]) {
        var clean = text
        var count = 0
        var findings: [AIWatermarkFinding] = []

        // Preamble regexes (e.g. "As an AI language model...", "Here is the summary you requested:")
        let preamblePatterns = [
            #"(?i)^\s*(?:as an ai language model,?\s*|as an ai assistant,?\s*|as an ai,?\s*)"#,
            #"(?i)^\s*(?:certainly!|sure!|absolutely!)\s+(?:here is|here's|below is)\s+[^:\n]+:\s*\n*"#,
            #"(?i)^\s*(?:here is|here's|below is)\s+(?:the|a)\s+[^:\n]+(?:\s+you requested)?:\s*\n*"#
        ]

        for pattern in preamblePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
                if let match = regex.firstMatch(in: clean, options: [], range: range) {
                    if let strRange = Range(match.range, in: clean) {
                        let preambleStr = String(clean[strRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        count += 1
                        findings.append(
                            AIWatermarkFinding(
                                kind: .aiChatbotSignature,
                                description: "AI conversational intro / preamble removed",
                                rawSample: preambleStr.count > 40 ? "\(preambleStr.prefix(40))…" : preambleStr,
                                cleanedReplacement: "[Removed]",
                                locationOffset: 0,
                                occurrenceCount: 1
                            )
                        )
                        clean.removeSubrange(strRange)
                    }
                }
            }
        }

        // Postamble / disclaimer regexes (e.g. "I hope this helps! Let me know if you need anything else.")
        let postamblePatterns = [
            #"(?i)\n+\s*(?:i hope this helps!?\s*(?:let me know if you (?:have any questions|need (?:anything|further) (?:else|assistance))\b\.?)?)\s*$"#,
            #"(?i)\n+\s*(?:let me know if you have (?:any )?(?:further )?questions\.?|feel free to ask if you (?:have|need) (?:more|any) questions\.?)\s*$"#,
            #"(?i)\n+\s*(?:note:\s*(?:this (?:response|content|summary) (?:is|was) generated by an ai (?:assistant|model)?\.?))\s*$"#
        ]

        for pattern in postamblePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
                if let match = regex.firstMatch(in: clean, options: [], range: range) {
                    if let strRange = Range(match.range, in: clean) {
                        let postambleStr = String(clean[strRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        count += 1
                        findings.append(
                            AIWatermarkFinding(
                                kind: .aiChatbotSignature,
                                description: "AI conversational sign-off / disclaimer removed",
                                rawSample: postambleStr.count > 40 ? "\(postambleStr.prefix(40))…" : postambleStr,
                                cleanedReplacement: "[Removed]",
                                locationOffset: 0,
                                occurrenceCount: 1
                            )
                        )
                        clean.removeSubrange(strRange)
                    }
                }
            }
        }

        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), count, findings)
    }

    // MARK: - Whitespace and Canonical Cleanup

    private func normalizeWhitespaceAndNFKC(_ text: String) -> String {
        // Apply Unicode NFKC canonical decomposition & recomposition
        var normalized = text.precomposedStringWithCanonicalMapping

        // Replace consecutive non-breaking spaces with standard space
        normalized = normalized.replacingOccurrences(of: "\u{00A0}", with: " ")
        normalized = normalized.replacingOccurrences(of: "\u{2007}", with: " ")
        normalized = normalized.replacingOccurrences(of: "\u{202F}", with: " ")

        return normalized
    }

    // MARK: - PDF Watermark Sanitization

    private func sanitizePDF(
        sourceURL: URL,
        targetURL: URL,
        options: AIWatermarkCleaningOptions
    ) throws -> (URL, AIWatermarkReport) {
        guard let document = PDFDocument(url: sourceURL) else {
            throw NSError(domain: "AIWatermarkSanitizerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document."])
        }

        var aggregatedText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageStr = page.string {
                aggregatedText += pageStr + "\n"
            }
        }

        let report = analyzeAndSanitize(text: aggregatedText, sourceName: sourceURL.lastPathComponent, options: options)

        // Strip AI-identifying metadata attributes from PDF
        var cleanAttributes = document.documentAttributes ?? [:]
        cleanAttributes[PDFDocumentAttribute.creatorAttribute] = "Storage Pal"
        cleanAttributes[PDFDocumentAttribute.producerAttribute] = "Storage Pal Sanitizer"
        cleanAttributes[PDFDocumentAttribute.authorAttribute] = nil
        cleanAttributes[PDFDocumentAttribute.subjectAttribute] = nil
        cleanAttributes[PDFDocumentAttribute.keywordsAttribute] = nil
        cleanAttributes["SynthesizedBy"] = nil
        cleanAttributes["WatermarkId"] = nil
        cleanAttributes["AI-Origin"] = nil
        cleanAttributes["xmp:CreatorTool"] = "Storage Pal"

        document.documentAttributes = cleanAttributes

        // Remove hidden annotations or invisible watermarks on each page
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let annotations = page.annotations
            for annotation in annotations {
                // If annotation has invisible flags or suspicious hidden watermark metadata
                if annotation.type == "Watermark" || annotation.contents?.contains("AI") == true || annotation.contents?.contains("Generated") == true {
                    page.removeAnnotation(annotation)
                }
            }
        }

        guard document.write(to: targetURL) else {
            throw NSError(domain: "AIWatermarkSanitizerService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to save sanitized PDF."])
        }

        return (targetURL, report)
    }
}
