import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

private enum SanitizerTab: String, CaseIterable, Identifiable {
    case sanitize = "Metadata Stripper"
    case redact = "Redaction & AI Proxy"
    case shred = "Secure Shredder"
    var id: String { rawValue }
}

@MainActor
struct ConfidentialSanitizerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: SanitizerTab = .sanitize

    // Metadata Sanitizer State
    @State private var inspectedItems: [SanitizerItem] = []

    // Redaction & AI Proxy State
    @State private var selectedTemplate: RedactionTemplateKind = .financial
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
        case .redact: "Document Redaction & AI Privacy Proxy"
        case .shred: "Permanent File Shredder"
        }
    }

    private var tabDetail: String {
        switch selectedTab {
        case .sanitize: "Strip hidden GPS coordinates, camera serials, and author metadata from photos and PDFs before sharing."
        case .redact: "Redact sensitive data with domain templates or swap real PII for synthetic tokens to safely query AI."
        case .shred: "Permanently obliterate confidential files with DoD 3-pass random and zero-fill cryptographic overwriting."
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
                            Text("REDACTION MODE")
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

                    Text(selectedTemplate.defaultDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)

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

                Button("Choose Document to Redact…") {
                    chooseDocumentToRedact()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
    }

    private func redactionDocumentCard(docURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: docURL.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.palMint)
                            .frame(width: 40, height: 40)
                            .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(docURL.lastPathComponent)
                                    .font(.system(size: 13, weight: .bold))
                                Text("\(redactionMatches.count) sensitive item(s)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.palMint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.palMint.opacity(0.12), in: Capsule())

                                if !manualRedactionBoxes.isEmpty {
                                    Text("\(manualRedactionBoxes.count) manual blackout(s)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }
                            Text("Template: \(selectedTemplate.rawValue) • Mode: \(selectedRedactionMode.rawValue)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }

                        Spacer()

                        Button("Choose Another…") {
                            chooseDocumentToRedact()
                        }
                        .buttonStyle(PalButtonStyle())
                    }

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
                                        rectNormalized: [min(1.0, max(0.0, x)), min(1.0, max(0.0, y)), min(1.0, max(0.05, w)), min(1.0, max(0.05, h))],
                                        pageIndex: 1
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
                isRedaction: false
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

    private func metadataBadges(for report: SanitizerMetadataReport) -> some View {
        HStack(spacing: 6) {
            if report.hasGPS, let coords = report.gpsCoordinates {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill")
                    Text("GPS: \(coords)")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12), in: Capsule())
            }

            if let camera = report.cameraModel {
                HStack(spacing: 3) {
                    Image(systemName: "camera.fill")
                    Text(camera)
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.palMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.palMuted.opacity(0.1), in: Capsule())
            }

            if let author = report.author {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                    Text(author)
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.palMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.palMuted.opacity(0.1), in: Capsule())
            }

            if report.tagsCount == 0 {
                Text("Clean (No Sensitive Tags)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.palMint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.palMint.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Secure Shredder Section

    private var shredderSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            PalCard(padding: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Permanent Destruction Protocol")
                            .font(.system(size: 13, weight: .bold))
                        Text("Standard macOS Trash deletion leaves magnetic data recoverable. Storage Pal Shredder performs 3-pass random byte and zero overwriting directly on the storage sectors.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }
                }
            }

            dropZone(
                label: "Drop files here to permanently shred with 3-pass overwrite",
                isShred: true,
                isRedaction: false
            )

            Button("Choose File to Permanently Shred…") {
                chooseFileToShred()
            }
            .buttonStyle(PalButtonStyle(prominent: true))
        }
    }

    private func dropZone(label: String, isShred: Bool, isRedaction: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isTargetedForDrop ? (isShred ? Color.red : Color.palMint) : Color.palCardBorder,
                style: StrokeStyle(lineWidth: 2, dash: [6])
            )
            .background(
                (isTargetedForDrop ? (isShred ? Color.red.opacity(0.08) : Color.palMint.opacity(0.08)) : Color.clear),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .frame(height: 90)
            .overlay(
                HStack(spacing: 12) {
                    Image(systemName: isShred ? "flame.fill" : (isRedaction ? "scissors" : "arrow.down.doc.fill"))
                        .font(.system(size: 22))
                        .foregroundStyle(isShred ? .red : (isTargetedForDrop ? Color.palMint : Color.palMuted))
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isShred ? .red : (isTargetedForDrop ? Color.palMint : Color.palMuted))
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleDroppedFiles(providers, isShred: isShred, isRedaction: isRedaction)
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

    private func handleDroppedFiles(_ providers: [NSItemProvider], isShred: Bool, isRedaction: Bool) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    if isShred {
                        self.shredTarget = url
                        self.isShowingShredConfirmation = true
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
}
