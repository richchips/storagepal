import Foundation
import PDFKit
import UniformTypeIdentifiers

actor AIWatermarkSanitizerService {
    static let shared = AIWatermarkSanitizerService()

    private let fm = FileManager.default

    init() {}

    // MARK: - Core Analysis & Sanitization (Zero-Width, Homoglyphs & Chatbot Wrappers)

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

    // MARK: - Statistical Watermark & Token Bias Analysis

    func analyzeStatisticalWatermark(text: String) -> StatisticalWatermarkMetrics {
        guard !text.isEmpty else {
            return .empty
        }

        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordCount = words.count
        guard wordCount > 0 else { return .empty }

        // Split sentences by terminal punctuation (. ! ?)
        let sentenceDelimiters = CharacterSet(charactersIn: ".!?\n")
        let rawSentences = text.components(separatedBy: sentenceDelimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 3 }

        let sentenceCount = max(1, rawSentences.count)
        let sentenceLengths = rawSentences.map { Double($0.split(separator: " ").count) }

        // Compute burstiness (Standard Deviation of sentence length)
        let meanLength = sentenceLengths.reduce(0.0, +) / Double(sentenceCount)
        let variance = sentenceLengths.map { pow($0 - meanLength, 2) }.reduce(0.0, +) / Double(sentenceCount)
        let burstinessScore = sqrt(variance)

        // Scan for statistical AI clichés and overrepresented green-list tokens
        var foundAIKeywords: [String] = []
        let lower = text.lowercased()
        for (cliche, _) in aiClicheDictionary {
            if lower.contains(cliche.lowercased()) {
                foundAIKeywords.append(cliche)
            }
        }

        let aiVocabPercent = (Double(foundAIKeywords.count) / Double(max(1, wordCount))) * 100.0

        // Estimated z-score simulation based on Kirchenbauer et al. green-list frequency
        // Natural human text: z < 1.0; Watermarked AI text: z > 2.0
        let greenListSimulatedRate = 0.25 + (Double(foundAIKeywords.count) * 0.04) + (burstinessScore < 4.5 ? 0.15 : 0.0)
        let totalTokens = Double(wordCount)
        let expected = 0.25 * totalTokens
        let stdDev = sqrt(totalTokens * 0.25 * 0.75)
        let estimatedGreenTokens = greenListSimulatedRate * totalTokens
        let zScore = max(0.0, (estimatedGreenTokens - expected) / max(1.0, stdDev))

        let risk: WatermarkRiskLevel
        if zScore > 2.2 || aiVocabPercent > 3.0 || (burstinessScore < 3.5 && wordCount > 40) {
            risk = .high
        } else if zScore > 1.2 || aiVocabPercent > 1.5 || (burstinessScore < 5.0 && wordCount > 25) {
            risk = .moderate
        } else {
            risk = .low
        }

        return StatisticalWatermarkMetrics(
            wordCount: wordCount,
            sentenceCount: sentenceCount,
            burstinessScore: (burstinessScore * 10).rounded() / 10,
            aiVocabularyDensityPercent: (aiVocabPercent * 10).rounded() / 10,
            estimatedZScore: (zScore * 10).rounded() / 10,
            tokenBiasRisk: risk,
            detectedAIKeywords: foundAIKeywords
        )
    }

    // MARK: - Statistical Token Bias & Rhythm Neutralizer

    func neutralizeTokenBias(
        text: String,
        level: HumanizationLevel
    ) -> (purifiedText: String, perturbations: [TokenPerturbation], metrics: StatisticalWatermarkMetrics) {
        guard !text.isEmpty else {
            return (text, [], .empty)
        }

        var working = text
        var perturbations: [TokenPerturbation] = []

        // Pass 1: Replace statistical AI clichés and signature buzzwords
        for (cliche, replacements) in aiClicheDictionary {
            guard let replacement = replacements.first else { continue }

            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: cliche) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                let matches = regex.matches(in: working, options: [], range: range)

                for match in matches.reversed() {
                    if let strRange = Range(match.range, in: working) {
                        let original = String(working[strRange])
                        // Match casing of original
                        let formattedReplacement = original.first?.isUppercase == true
                            ? replacement.prefix(1).uppercased() + replacement.dropFirst()
                            : replacement

                        working.replaceSubrange(strRange, with: formattedReplacement)
                        perturbations.append(
                            TokenPerturbation(
                                originalWord: original,
                                replacementWord: formattedReplacement,
                                reason: "Neutralized statistical AI buzzword (\(cliche))",
                                offset: match.range.location
                            )
                        )
                    }
                }
            }
        }

        // Pass 2: $n$-Gram Hash Disruptor (Modulate transition connectors and conjunctions)
        let transitionPerturbations: [(pattern: String, replacements: [String])] = [
            (#"(?i)\bhowever,\b"#, ["Yet,", "Still,", "On the other hand,", "Even so,"]),
            (#"(?i)\bfurthermore,\b"#, ["Also,", "In addition,", "What's more,", "Beyond that,"]),
            (#"(?i)\bmoreover,\b"#, ["Also,", "Plus,", "In addition,", "Alongside this,"]),
            (#"(?i)\btherefore,\b"#, ["So,", "As a result,", "Because of this,", "Thus,"]),
            (#"(?i)\bconsequently,\b"#, ["As a result,", "Because of this,", "Hence,"]),
            (#"(?i)\badditionally,\b"#, ["Also,", "What's more,", "On top of that,"]),
            (#"(?i)\bspecifically,\b"#, ["In particular,", "Namely,", "More precisely,"]),
            (#"(?i)\bfor instance,\b"#, ["For example,", "As an example,", "To illustrate,"]),
            (#"(?i)\bultimately,\b"#, ["In the end,", "Finally,", "At the end of the day,"]),
            (#"(?i)\bin particular,\b"#, ["Specifically,", "Especially,", "Mainly,"])
        ]

        var transitionIndex = 0
        for item in transitionPerturbations {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: []) {
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                let matches = regex.matches(in: working, options: [], range: range)

                for match in matches.reversed() {
                    if let strRange = Range(match.range, in: working) {
                        let original = String(working[strRange])
                        let replacement = item.replacements[transitionIndex % item.replacements.count]
                        transitionIndex += 1

                        working.replaceSubrange(strRange, with: replacement)
                        perturbations.append(
                            TokenPerturbation(
                                originalWord: original,
                                replacementWord: replacement,
                                reason: "Desynchronized n-gram hash chain transition",
                                offset: match.range.location
                            )
                        )
                    }
                }
            }
        }

        // Pass 3: Sentence Burstiness & Cadence Modulation (Balanced & Deep)
        if level == .balanced || level == .deepNatural {
            working = injectSentenceBurstiness(text: working, level: level, perturbations: &perturbations)
        }

        let newMetrics = analyzeStatisticalWatermark(text: working)
        return (working, perturbations, newMetrics)
    }

    private func injectSentenceBurstiness(
        text: String,
        level: HumanizationLevel,
        perturbations: inout [TokenPerturbation]
    ) -> String {
        var result = text

        // Break rigid compound clauses joined with repeating semicolons or excessive conjunctions
        let rigidPatterns = [
            ("; however, ", ". Yet, "),
            ("; furthermore, ", ". Also, "),
            ("; moreover, ", ". What's more, "),
            ("; therefore, ", ". So, "),
            (", which subsequently leads to ", ". This leads to "),
            (", which in turn highlights ", ". This highlights ")
        ]

        for (pattern, replacement) in rigidPatterns {
            if result.contains(pattern) {
                result = result.replacingOccurrences(of: pattern, with: replacement)
                perturbations.append(
                    TokenPerturbation(
                        originalWord: pattern.trimmingCharacters(in: .whitespaces),
                        replacementWord: replacement.trimmingCharacters(in: .whitespaces),
                        reason: "Modulated sentence cadence & increased burstiness variance",
                        offset: 0
                    )
                )
            }
        }

        return result
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

    // MARK: - Curated AI Cliché & Token Bias Dictionary

    private let aiClicheDictionary: [String: [String]] = [
        "delve into": ["explore", "look into", "examine", "investigate"],
        "delves into": ["explores", "looks into", "examines"],
        "delving into": ["exploring", "looking into", "examining"],
        "tapestry of": ["range of", "collection of", "variety of", "blend of"],
        "rich tapestry": ["wide variety", "complex mix", "diverse range"],
        "intricate tapestry": ["layered mix", "complex network"],
        "testament to": ["proof of", "evidence of", "sign of"],
        "standing as a testament to": ["proving", "demonstrating", "showing"],
        "beacon of": ["symbol of", "example of", "guide for"],
        "fosters": ["encourages", "promotes", "supports", "builds"],
        "fostering": ["encouraging", "promoting", "supporting"],
        "underscores": ["highlights", "shows", "stresses", "points out"],
        "underscoring": ["highlighting", "showing", "pointing to"],
        "crucial": ["key", "important", "essential", "vital"],
        "pivotal": ["critical", "key", "central", "main"],
        "paramount": ["vital", "top priority", "essential"],
        "cornerstone": ["foundation", "basis", "core element"],
        "multifaceted": ["complex", "varied", "layered", "diverse"],
        "ever-evolving": ["changing", "developing", "shifting"],
        "seamlessly integrates": ["works smoothly with", "connects directly with"],
        "seamlessly": ["smoothly", "easily", "directly"],
        "navigate the complexities": ["handle the challenges", "manage the details", "work through"],
        "navigate": ["manage", "handle", "deal with", "work through"],
        "harness the power of": ["use", "apply", "take advantage of"],
        "harnessing": ["using", "applying", "leveraging"],
        "shed light on": ["clarify", "explain", "highlight"],
        "sheds light on": ["clarifies", "explains", "highlights"],
        "embark on a journey": ["start out", "begin", "set out"],
        "poised to": ["ready to", "set to", "prepared to"],
        "it is important to note that": ["note that", "importantly,", ""],
        "it is worth noting that": ["notably,", "keep in mind that", ""],
        "it should be noted that": ["note that", "importantly,", ""],
        "in conclusion": ["overall,", "to wrap up,", "in summary,"],
        "at the forefront of": ["leading", "pioneering", "heading"],
        "plays a vital role in": ["is important for", "helps with", "shapes"],
        "a myriad of": ["many", "numerous", "a wide range of"],
        "game-changer": ["major shift", "breakthrough", "significant step forward"]
    ]

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
        let homoglyphMap: [Character: Character] = [
            "\u{0430}": "a", "\u{0435}": "e", "\u{043E}": "o", "\u{0440}": "p", "\u{0441}": "s",
            "\u{0443}": "y", "\u{0445}": "x", "\u{0456}": "i", "\u{0458}": "j",
            "\u{0410}": "A", "\u{0412}": "B", "\u{0415}": "E", "\u{041A}": "K", "\u{041C}": "M",
            "\u{041D}": "H", "\u{041E}": "O", "\u{0420}": "P", "\u{0421}": "C", "\u{0422}": "T",
            "\u{0425}": "X",
            "\u{0391}": "A", "\u{0392}": "B", "\u{0395}": "E", "\u{0396}": "Z", "\u{0397}": "H",
            "\u{0399}": "I", "\u{039A}": "K", "\u{039C}": "M", "\u{039D}": "N", "\u{039F}": "O",
            "\u{03A1}": "P", "\u{03A4}": "T", "\u{03A5}": "Y", "\u{03A7}": "X", "\u{03BF}": "o",
            "\u{03BD}": "v", "\u{03C1}": "p"
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
        var normalized = text.precomposedStringWithCanonicalMapping
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

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let annotations = page.annotations
            for annotation in annotations {
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
