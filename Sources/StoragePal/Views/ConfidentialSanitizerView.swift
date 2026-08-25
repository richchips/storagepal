import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

private enum SanitizerTab: String, CaseIterable, Identifiable {
    case sanitize = "Metadata Stripper"
    case aiWatermark = "AI Watermark Remover"
    case redact = "Redaction & AI Proxy"
    case shred = "Secure Shredder"
    var id: String { rawValue }
}

private enum AIWatermarkInputMode: String, CaseIterable, Identifiable {
    case scratchpad = "Text Scratchpad"
    case documentFile = "Document File Scan"
    var id: String { rawValue }
}

@MainActor
struct ConfidentialSanitizerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: SanitizerTab = .sanitize

    // Metadata Sanitizer State
    @State private var inspectedItems: [SanitizerItem] = []

    // AI Watermark Remover State
    @State private var aiInputMode: AIWatermarkInputMode = .scratchpad
    @State private var aiRawInputText: String = ""
    @State private var aiWatermarkReport: AIWatermarkReport = .empty
    @State private var aiCleaningOptions: AIWatermarkCleaningOptions = AIWatermarkCleaningOptions()
    @State private var aiSourceFileURL: URL?
    @State private var isShowingVisualMarkers: Bool = false

    // Redaction & AI Proxy State
    @State private var selectedTemplate: RedactionTemplateKind = .clinicalPsychology
    @State private var selectedPrivacyPolicy: PrivacyPolicyTier = .internalClinical
    @State private var selectedRedactionMode: RedactionMode = .aiTokenSwap
    @State private var selectedAIPromptRole: AIPromptRolePreset = .general
    @State private var redactionSourceURL: URL?
    @State private var redactionMatches: [SensitiveEntityMatch] = []
    @State private var manualRedactionBoxes: [ManualRedactionBox] = []
    @State private var redactionFullText: String = ""
    @State private var customKeywordsText = "ProjectTitan, SecretKey, InternalAlpha"
    @State private var customRegexText = ""
    @State private var isShowingRestoreSheet = false

    // Shredder State
    @State private var shredTarget: URL?
    @State private var isShowingShredConfirmation = false

    // General State
    @State private var statusMessage: String?
    @State private var isTargetedForDrop = false
    @State private var previewURL: URL?

    private let sanitizer = MetadataSanitizerService()
    private let shredder = SecureShredderService()
    private let redactionEngine = DocumentRedactionEngine()
    private let tokenService = AITokenSwapService.shared
    private let aiWatermarkService = AIWatermarkSanitizerService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Sanitize & Protect",
                        title: tabTitle,
                        detail: tabDetail
                    )
                    Spacer()
                    if selectedTab == .redact {
                        Button {
                            isShowingRestoreSheet = true
                        } label: {
                            Label("Restore Real Data from AI…", systemImage: "sparkles.rectangle.stack.fill")
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))
                    }
                }

                Picker("Tool", selection: $selectedTab) {
                    ForEach(SanitizerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if let msg = statusMessage {
                    PalCard(padding: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.palMint)
                            Text(msg)
                                .font(.system(size: 12))
                            Spacer()
                            Button { statusMessage = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                switch selectedTab {
                case .sanitize:
                    sanitizerSection
                case .aiWatermark:
                    aiWatermarkSection
                case .redact:
                    redactionSection
                case .shred:
                    shredderSection
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $isShowingRestoreSheet) {
            AITokenRestoreSheet()
        }
        .confirmationDialog(
            "Permanently Shred File?",
            isPresented: $isShowingShredConfirmation,
            titleVisibility: .visible
        ) {
            Button("Permanently Shred File", role: .destructive) {
                if let target = shredTarget {
                    executeShred(target)
                }
            }
            Button("Cancel", role: .cancel) { shredTarget = nil }
        } message: {
            Text("This file will be cryptographically overwritten with multiple random and zero passes. It cannot be recovered from Trash or disk recovery tools.")
        }
    }

    private var tabTitle: String {
        switch selectedTab {
        case .sanitize: "Confidential Metadata Stripper"
        case .aiWatermark: "AI Watermark & Steganography Purifier"
        case .redact: "Document Redaction & AI Privacy Proxy"
        case .shred: "Permanent DoD File Shredder"
        }
    }

    private var tabDetail: String {
        switch selectedTab {
        case .sanitize: "Strip hidden GPS coordinates, camera serials, and author metadata from photos and PDFs before sharing."
        case .aiWatermark: "Detect, visualize, and strip hidden zero-width markers, variation selectors, homoglyph lookalikes, and chatbot preambles from AI-generated text."
        case .redact: "Redact sensitive data with domain templates or swap real PII for synthetic tokens to safely query AI."
        case .shred: "Permanently obliterate confidential files with DoD 3-pass random and zero-fill cryptographic overwriting."
        }
    }

    // MARK: - AI Watermark Remover Section

    private var aiWatermarkSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Configuration & Rules Card
            PalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("AI WATERMARK CLEANING RULES", systemImage: "slider.horizontal.3")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.palMint)
                        Spacer()
                        Picker("Input Mode", selection: $aiInputMode) {
                            ForEach(AIWatermarkInputMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }

                    Divider()

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        Toggle("Strip Zero-Width & Hidden Unicode (U+200B, U+FEFF, ZWJ)", isOn: $aiCleaningOptions.stripInvisibleUnicode)
                            .font(.system(size: 11))
                            .onChange(of: aiCleaningOptions.stripInvisibleUnicode) { reanalyzeAIText() }

                        Toggle("Normalize Confusable Homoglyphs (Cyrillic/Greek lookalikes)", isOn: $aiCleaningOptions.normalizeHomoglyphs)
                            .font(.system(size: 11))
                            .onChange(of: aiCleaningOptions.normalizeHomoglyphs) { reanalyzeAIText() }

                        Toggle("Strip AI Chatbot Preambles & Disclaimers", isOn: $aiCleaningOptions.stripAIPromptArtifacts)
                            .font(.system(size: 11))
                            .onChange(of: aiCleaningOptions.stripAIPromptArtifacts) { reanalyzeAIText() }

                        Toggle("Normalize Non-Breaking Whitespace & NFKC", isOn: $aiCleaningOptions.normalizeWhitespace)
                            .font(.system(size: 11))
                            .onChange(of: aiCleaningOptions.normalizeWhitespace) { reanalyzeAIText() }
                    }
                }
            }

            if aiInputMode == .scratchpad {
                // Interactive Text Scratchpad Card
                PalCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("PASTE AI-GENERATED TEXT")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.palMint)

                            Spacer()

                            if !aiRawInputText.isEmpty {
                                if aiWatermarkReport.totalWatermarksFound == 0 {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(Color.palMint)
                                        Text("100% Watermark-Free & Clean")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.palMint)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.palMint.opacity(0.12), in: Capsule())
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text("\(aiWatermarkReport.totalWatermarksFound) AI Watermark(s) Detected (\(aiWatermarkReport.steganographyConfidencePercent)% Confidence)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }
                        }

                        // Text input editor
                        ZStack(alignment: .topLeading) {
                            if aiRawInputText.isEmpty {
                                Text("Paste text generated by ChatGPT, Claude, Gemini, Copilot, or LLMs here to detect and strip hidden zero-width characters, variation selectors, homoglyphs, and canned conversational intros…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.palMuted)
                                    .padding(8)
                            }

                            TextEditor(text: $aiRawInputText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 140, maxHeight: 200)
                                .padding(4)
                                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.palCardBorder, lineWidth: 1)
                                )
                                .onChange(of: aiRawInputText) {
                                    reanalyzeAIText()
                                }
                        }

                        // Watermark Category Summary Pills
                        if !aiRawInputText.isEmpty && aiWatermarkReport.totalWatermarksFound > 0 {
                            HStack(spacing: 10) {
                                if aiWatermarkReport.invisibleCharactersCount > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.slash.fill")
                                        Text("Zero-Width / Invisible: \(aiWatermarkReport.invisibleCharactersCount)")
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.red)
                                }

                                if aiWatermarkReport.homoglyphsCount > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "character.phonetic")
                                        Text("Homoglyphs: \(aiWatermarkReport.homoglyphsCount)")
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.orange)
                                }

                                if aiWatermarkReport.aiSignaturesCount > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bubble.left.and.bubble.right.fill")
                                        Text("Chatbot Preambles: \(aiWatermarkReport.aiSignaturesCount)")
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.purple)
                                }
                            }
                        }

                        // Preview / Purified Output Card
                        if !aiRawInputText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(isShowingVisualMarkers ? "RAW TEXT WITH VISUALIZED MARKERS" : "PURIFIED SANITIZED TEXT")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1)
                                        .foregroundStyle(Color.palMuted)
                                    Spacer()
                                    Toggle("Visualize Hidden Markers", isOn: $isShowingVisualMarkers)
                                        .font(.system(size: 10))
                                }

                                ScrollView {
                                    Text(isShowingVisualMarkers ? aiWatermarkReport.rawWithVisualMarkers : aiWatermarkReport.purifiedText)
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineSpacing(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                }
                                .frame(height: 120)
                                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.palCardBorder, lineWidth: 1)
                                )

                                HStack(spacing: 12) {
                                    Button("Clear") {
                                        aiRawInputText = ""
                                        aiWatermarkReport = .empty
                                    }
                                    .buttonStyle(PalButtonStyle())

                                    Spacer()

                                    Button {
                                        copyPurifiedText()
                                    } label: {
                                        Label("Copy Purified Clean Text", systemImage: "doc.on.doc.fill")
                                    }
                                    .buttonStyle(PalButtonStyle(prominent: true))
                                }
                            }
                        }
                    }
                }
            } else {
                // Document File Scan
                VStack(alignment: .leading, spacing: 16) {
                    dropZone(
                        label: "Drop PDF, Markdown (.md), or Text (.txt) document here to strip AI watermarks",
                        isShred: false,
                        isRedaction: false,
                        isAIWatermark: true
                    )

                    if let fileURL = aiSourceFileURL {
                        PalCard(padding: 16) {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: fileURL.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.palMint)
                                    .frame(width: 44, height: 44)
                                    .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(fileURL.lastPathComponent)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(aiWatermarkReport.totalWatermarksFound == 0 ? "Clean" : "\(aiWatermarkReport.totalWatermarksFound) watermarks stripped")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(aiWatermarkReport.totalWatermarksFound == 0 ? Color.palMint.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                                            .foregroundStyle(aiWatermarkReport.totalWatermarksFound == 0 ? Color.palMint : .orange)
                                    }

                                    if !aiWatermarkReport.findings.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(aiWatermarkReport.findings.prefix(3)) { finding in
                                                HStack(spacing: 6) {
                                                    Text(finding.kind.shortTag)
                                                        .font(.system(size: 8, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                                        .foregroundStyle(.red)
                                                    Text("\(finding.description) (\(finding.occurrenceCount)x)")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(Color.palMuted)
                                                }
                                            }
                                        }
                                    }
                                }

                                Spacer()

                                Button("Export Purified Copy…") {
                                    exportPurifiedFile()
                                }
                                .buttonStyle(PalButtonStyle(prominent: true))

                                Button {
                                    aiSourceFileURL = nil
                                    aiWatermarkReport = .empty
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reanalyzeAIText() {
        Task {
            let report = await aiWatermarkService.analyzeAndSanitize(
                text: aiRawInputText,
                sourceName: "Scratchpad",
                options: aiCleaningOptions
            )
            self.aiWatermarkReport = report
        }
    }

    private func copyPurifiedText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(aiWatermarkReport.purifiedText, forType: .string)
        statusMessage = "Copied purified clean text to clipboard (stripped \(aiWatermarkReport.totalWatermarksFound) watermarks)."
    }

    private func exportPurifiedFile() {
        guard let sourceURL = aiSourceFileURL else { return }
        let ext = sourceURL.pathExtension.lowercased()

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(sourceURL.deletingPathExtension().lastPathComponent)_ai_purified.\(ext)"
        panel.prompt = "Save Clean Copy"

        if panel.runModal() == .OK, let targetURL = panel.url {
            Task {
                do {
                    let destDir = targetURL.deletingLastPathComponent()
                    let (resultURL, report) = try await aiWatermarkService.sanitizeFile(
                        at: sourceURL,
                        destinationDirectory: destDir,
                        options: aiCleaningOptions
                    )
                    if resultURL != targetURL {
                        try? FileManager.default.removeItem(at: targetURL)
                        try? FileManager.default.moveItem(at: resultURL, to: targetURL)
                    }
                    statusMessage = "Saved clean document (\(report.totalWatermarksFound) watermarks stripped) to \(targetURL.lastPathComponent)."
                } catch {
                    statusMessage = "Failed to export: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Redaction & AI Proxy Section

    private var redactionSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Configuration Card
            PalCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DOCUMENT TEMPLATE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.palMint)
                            Picker("", selection: $selectedTemplate) {
                                ForEach(RedactionTemplateKind.allCases) { t in
                                    Label(t.rawValue, systemImage: t.symbol).tag(t)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedTemplate) {
                                reanalyzeRedactionDocument()
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("PRIVACY POLICY")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.palMint)
                            Picker("", selection: $selectedPrivacyPolicy) {
                                ForEach(PrivacyPolicyTier.allCases) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedPrivacyPolicy) {
                                reanalyzeRedactionDocument()
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("OUTPUT MODE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.palMint)
                            Picker("", selection: $selectedRedactionMode) {
                                ForEach(RedactionMode.allCases) { m in
                                    Label(m.rawValue, systemImage: m.symbol).tag(m)
                                }
                            }
                            .labelsHidden()
                        }

                        if selectedRedactionMode == .aiTokenSwap {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("AI PROMPT ROLE")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(Color.palMint)
                                Picker("", selection: $selectedAIPromptRole) {
                                    ForEach(AIPromptRolePreset.allCases) { r in
                                        Label(r.rawValue, systemImage: r.symbol).tag(r)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedTemplate.defaultDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                        Text("Policy: \(selectedPrivacyPolicy.summary)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.palMint)
                    }

                    if selectedTemplate == .custom {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom Keywords (comma-separated):")
                                .font(.system(size: 11, weight: .semibold))
                            TextField("ProjectTitan, InternalAlpha, SecretKey", text: $customKeywordsText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: customKeywordsText) {
                                    reanalyzeRedactionDocument()
                                }
                        }
                    }
                }
            }

            // Drop zone or Document Card
            if let docURL = redactionSourceURL {
                redactionDocumentCard(docURL: docURL)
            } else {
                dropZone(
                    label: "Drop PDF contract, tax return, resume, or text document here to scan",
                    isShred: false,
                    isRedaction: true
                )
            }
        }
    }

    private func redactionDocumentCard(docURL: URL) -> some View {
        VStack(spacing: 16) {
            PalCard(padding: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: docURL.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.palMint)
                        .frame(width: 44, height: 44)
                        .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(docURL.lastPathComponent)
                            .font(.system(size: 14, weight: .bold))
                        HStack(spacing: 8) {
                            Text("\(redactionMatches.count) sensitive items detected")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(redactionMatches.isEmpty ? Color.palMint : Color.palMint)
                            if !manualRedactionBoxes.isEmpty {
                                Text("• \(manualRedactionBoxes.count) manual boxes")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.palMuted)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        previewURL = docURL
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(PalButtonStyle())

                    Button {
                        redactionSourceURL = nil
                        redactionMatches.removeAll()
                        manualRedactionBoxes.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    // Manual Drag-to-Redact Box Canvas Info
                    if docURL.pathExtension.lowercased() == "pdf" {
                        Divider()
                        HStack {
                            Label("Visual Redaction Canvas: Drag to black out stamps, logos, or signatures", systemImage: "paintbrush.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)

                            Spacer()

                            if !manualRedactionBoxes.isEmpty {
                                Button("Clear Manual Boxes (\(manualRedactionBoxes.count))") {
                                    manualRedactionBoxes.removeAll()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            }
                        }

                        // Interactive canvas drawing zone
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.9))
                                .frame(height: 140)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.palCardBorder, lineWidth: 1)
                                )

                            Text("Click & drag inside this box to place visual blackout blocks over non-text elements (signatures, stamps, barcodes).")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted.opacity(0.6))
                                .padding(12)

                            // Render drawn manual boxes
                            GeometryReader { geo in
                                ForEach(manualRedactionBoxes) { box in
                                    if box.rectNormalized.count == 4 {
                                        let x = box.rectNormalized[0] * geo.size.width
                                        let y = box.rectNormalized[1] * geo.size.height
                                        let w = box.rectNormalized[2] * geo.size.width
                                        let h = box.rectNormalized[3] * geo.size.height

                                        Rectangle()
                                            .fill(Color.black.opacity(0.85))
                                            .frame(width: max(10, w), height: max(10, h))
                                            .position(x: x + w / 2, y: y + h / 2)
                                    }
                                }
                            }
                        }
                        .frame(height: 140)
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onEnded { value in
                                    let w = abs(value.translation.width) / 800.0
                                    let h = abs(value.translation.height) / 140.0
                                    let x = min(value.startLocation.x, value.location.x) / 800.0
                                    let y = min(value.startLocation.y, value.location.y) / 140.0
                                    let box = ManualRedactionBox(
                                        id: UUID(),
                                        rectNormalized: [Double(x), Double(y), Double(w), Double(h)],
                                        pageIndex: 0
                                    )
                                    manualRedactionBoxes.append(box)
                                }
                        )
                    }
                }
            }

            if redactionMatches.isEmpty && manualRedactionBoxes.isEmpty {
                PalCard {
                    HStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Sensitive Data Detected")
                                .font(.system(size: 13, weight: .bold))
                            Text("No items matching the '\(selectedTemplate.rawValue)' template rules were found in this document.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                // Matches checklist
                VStack(spacing: 8) {
                    ForEach($redactionMatches) { $match in
                        PalCard(padding: 12) {
                            HStack(spacing: 12) {
                                Toggle("", isOn: $match.isEnabled)
                                    .labelsHidden()

                                Text(match.category)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.palMint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                                if match.tier == .quasiIdentifier {
                                    Text("Quasi-ID")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }

                                Text(match.originalText)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                Text(selectedRedactionMode == .aiTokenSwap ? match.tokenReplacement : (selectedRedactionMode == .blackout ? "██████" : "[REDACTED]"))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(selectedRedactionMode == .aiTokenSwap ? Color.palMint : Color.palMuted)

                                Spacer()

                                Text("Page \(match.pageIndex)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Action Bar
                HStack(spacing: 12) {
                    Spacer()

                    if selectedRedactionMode == .aiTokenSwap {
                        Button {
                            copyAIPrompt()
                        } label: {
                            Label("Copy Prompt for AI (\(selectedAIPromptRole.rawValue))", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))

                        Button("Export AI-Safe Document…") {
                            exportRedactedDocument()
                        }
                        .buttonStyle(PalButtonStyle())
                    } else {
                        Button("Export Redacted Document…") {
                            exportRedactedDocument()
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))
                    }
                }
            }
        }
    }

    private func chooseDocumentToRedact() {
        chooseRedactionDocument()
    }

    private func chooseRedactionDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText, .utf8PlainText]
        panel.prompt = "Analyze Document"
        if panel.runModal() == .OK, let url = panel.url {
            self.redactionSourceURL = url
            self.manualRedactionBoxes.removeAll()
            reanalyzeRedactionDocument()
        }
    }

    private func reanalyzeRedactionDocument() {
        guard let url = redactionSourceURL else { return }
        Task {
            let keywords = customKeywordsText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let (matches, text) = await redactionEngine.scanDocument(
                at: url,
                template: selectedTemplate,
                policy: selectedPrivacyPolicy,
                customKeywords: keywords,
                customRegex: customRegexText.isEmpty ? nil : customRegexText
            )
            self.redactionMatches = matches
            self.redactionFullText = text
        }
    }

    private func copyAIPrompt() {
        guard let docURL = redactionSourceURL else { return }
        let session = tokenService.createSession(
            documentName: docURL.lastPathComponent,
            template: selectedTemplate,
            matches: redactionMatches
        )
        Task {
            let tokenizedText = await redactionEngine.redactText(
                originalText: redactionFullText,
                matches: redactionMatches,
                mode: .aiTokenSwap
            )
            let prompt = await redactionEngine.generateAIPrompt(
                role: selectedAIPromptRole,
                documentName: docURL.lastPathComponent,
                tokenizedText: tokenizedText
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            statusMessage = "Copied \(selectedAIPromptRole.rawValue) AI prompt to clipboard! Token session '\(session.documentName)' created."
        }
    }

    private func exportRedactedDocument() {
        guard let docURL = redactionSourceURL else { return }
        let ext = docURL.pathExtension.lowercased()

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(docURL.deletingPathExtension().lastPathComponent)_sanitized.\(ext)"
        panel.prompt = "Save Sanitize Copy"

        if panel.runModal() == .OK, let targetURL = panel.url {
            Task {
                do {
                    if ext == "pdf" {
                        try await redactionEngine.redactPDF(
                            sourceURL: docURL,
                            matches: redactionMatches,
                            manualBoxes: manualRedactionBoxes,
                            mode: selectedRedactionMode,
                            targetURL: targetURL
                        )
                    } else {
                        let text = await redactionEngine.redactText(
                            originalText: redactionFullText,
                            matches: redactionMatches,
                            mode: selectedRedactionMode
                        )
                        try text.write(to: targetURL, atomically: true, encoding: .utf8)
                    }

                    if selectedRedactionMode == .aiTokenSwap {
                        _ = tokenService.createSession(
                            documentName: docURL.lastPathComponent,
                            template: selectedTemplate,
                            matches: redactionMatches
                        )
                    }

                    statusMessage = "Saved sanitized document to \(targetURL.lastPathComponent)."
                } catch {
                    statusMessage = "Failed to export: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Metadata Sanitizer Section

    private var sanitizerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            dropZone(
                label: "Drop photos or PDFs here to inspect & strip hidden metadata",
                isShred: false,
                isRedaction: false,
                isAIWatermark: false
            )

            HStack {
                Button("Choose Files to Sanitize…") {
                    chooseFilesToSanitize()
                }
                .buttonStyle(PalButtonStyle(prominent: true))

                Spacer()

                if !inspectedItems.isEmpty {
                    Button("Sanitize All (\(inspectedItems.count))") {
                        sanitizeAllItems()
                    }
                    .buttonStyle(PalButtonStyle())
                }
            }

            if inspectedItems.isEmpty {
                PalCard {
                    HStack(spacing: 20) {
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Files Selected")
                                .font(.system(size: 15, weight: .bold))
                            Text("Add images or PDF contracts to inspect hidden geolocation tags, device information, and document histories.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(inspectedItems) { item in
                        PalCard(padding: 16) {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.fileExtension == "pdf" ? "doc.richtext" : "photo")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.palMint)
                                    .frame(width: 40, height: 40)
                                    .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(item.name)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(ByteText.string(item.bytes))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.palMuted)
                                    }

                                    metadataBadges(for: item.report)
                                }

                                Spacer()

                                Button {
                                    previewURL = item.url
                                } label: {
                                    Image(systemName: "eye")
                                }
                                .buttonStyle(PalButtonStyle())

                                Button("Sanitize…") {
                                    sanitizeSingleItem(item)
                                }
                                .buttonStyle(PalButtonStyle(prominent: true))

                                Button {
                                    inspectedItems.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shredder Section

    private var shredderSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            dropZone(
                label: "Drop file here to permanently destroy and cryptographically overwrite",
                isShred: true,
                isRedaction: false,
                isAIWatermark: false
            )

            HStack {
                Button("Choose File to Shred…") {
                    chooseFileToShred()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
                Spacer()
            }

            PalCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(Color.palMint)
                        Text("Permanent Overwrite Specification")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("Storage Pal performs DoD 5220.22-M 3-pass sanitization: writing random cryptosequences, the bitwise complement, zero fills, and issuing hardware F_FULLFSYNC flushes.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
            }
        }
    }

    // MARK: - Drop Zone Helper

    private func dropZone(label: String, isShred: Bool, isRedaction: Bool, isAIWatermark: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(
                isShred ? Color.red.opacity(0.6) : (isTargetedForDrop ? Color.palMint : Color.palCardBorder),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
            .background(
                isShred ? Color.red.opacity(0.04) : (isTargetedForDrop ? Color.palMint.opacity(0.06) : Color.white.opacity(0.4)),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .frame(height: 110)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: isShred ? "flame.fill" : (isAIWatermark ? "sparkles.rectangle.stack" : (isRedaction ? "doc.text.magnifyingglass" : "arrow.down.doc.fill")))
                        .font(.system(size: 24))
                        .foregroundStyle(isShred ? .red : Color.palMint)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isShred ? .red : (isTargetedForDrop ? Color.palMint : Color.palMuted))
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleDroppedFiles(providers, isShred: isShred, isRedaction: isRedaction, isAIWatermark: isAIWatermark)
                return true
            }
    }

    // MARK: - Actions

    private func chooseFilesToSanitize() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Inspect Metadata"
        if panel.runModal() == .OK {
            for url in panel.urls {
                Task {
                    let report = await sanitizer.inspectMetadata(for: url)
                    let item = SanitizerItem(
                        url: url,
                        name: url.lastPathComponent,
                        bytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0),
                        fileExtension: url.pathExtension.lowercased(),
                        report: report
                    )
                    inspectedItems.append(item)
                }
            }
        }
    }

    private func sanitizeSingleItem(_ item: SanitizerItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Clean Copy"
        if panel.runModal() == .OK, let dest = panel.url {
            Task {
                do {
                    let cleanURL = try await sanitizer.sanitizeFile(at: item.url, destinationDirectory: dest)
                    statusMessage = "Sanitized copy saved to \(cleanURL.lastPathComponent)."
                    inspectedItems.removeAll { $0.id == item.id }
                } catch {
                    statusMessage = "Failed to sanitize: \(error.localizedDescription)"
                }
            }
        }
    }

    private func sanitizeAllItems() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save All Clean Copies"
        if panel.runModal() == .OK, let dest = panel.url {
            Task {
                var count = 0
                for item in inspectedItems {
                    if (try? await sanitizer.sanitizeFile(at: item.url, destinationDirectory: dest)) != nil {
                        count += 1
                    }
                }
                statusMessage = "Successfully sanitized \(count) file(s)."
                inspectedItems.removeAll()
            }
        }
    }

    private func chooseFileToShred() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Select to Shred"
        if panel.runModal() == .OK, let url = panel.url {
            shredTarget = url
            isShowingShredConfirmation = true
        }
    }

    private func executeShred(_ url: URL) {
        Task {
            do {
                try await shredder.shredFile(at: url)
                statusMessage = "Permanently shredded “\(url.lastPathComponent)”."
                shredTarget = nil
            } catch {
                statusMessage = "Shredding error: \(error.localizedDescription)"
            }
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider], isShred: Bool, isRedaction: Bool, isAIWatermark: Bool = false) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    if isShred {
                        self.shredTarget = url
                        self.isShowingShredConfirmation = true
                    } else if isAIWatermark {
                        self.aiSourceFileURL = url
                        self.aiInputMode = .documentFile
                        if let content = try? String(contentsOf: url, encoding: .utf8) {
                            self.aiWatermarkReport = await self.aiWatermarkService.analyzeAndSanitize(
                                text: content,
                                sourceName: url.lastPathComponent,
                                options: self.aiCleaningOptions
                            )
                        }
                    } else if isRedaction {
                        self.redactionSourceURL = url
                        self.reanalyzeRedactionDocument()
                    } else {
                        let report = await self.sanitizer.inspectMetadata(for: url)
                        let sanitizerItem = SanitizerItem(
                            url: url,
                            name: url.lastPathComponent,
                            bytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0),
                            fileExtension: url.pathExtension.lowercased(),
                            report: report
                        )
                        self.inspectedItems.append(sanitizerItem)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metadataBadges(for report: SanitizerMetadataReport) -> some View {
        HStack(spacing: 8) {
            if report.hasGPS {
                Label(report.gpsCoordinates ?? "GPS Geolocation", systemImage: "location.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12), in: Capsule())
            }

            if let camera = report.cameraModel {
                Label(camera, systemImage: "camera.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.palMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.palMist, in: Capsule())
            }

            if let author = report.author {
                Label(author, systemImage: "person.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.palMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.palMist, in: Capsule())
            }
        }
    }
}
