import AppKit
import QuickLook
import SwiftUI

struct DuplicateFinderView: View {
    @EnvironmentObject private var model: AppModel
    @State private var targetFolderURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var duplicateGroups: [DuplicateFileGroup] = []
    @State private var isScanning = false
    @State private var minSizeOption: MinSizeOption = .tenMB
    @State private var previewURL: URL?
    @State private var copiedReport = false

    private let duplicateService = DuplicateFinderService()

    private enum MinSizeOption: Int64, CaseIterable, Identifiable {
        case oneMB = 1_000_000
        case tenMB = 10_000_000
        case fiftyMB = 50_000_000
        case hundredMB = 100_000_000

        var id: Int64 { rawValue }
        var title: String {
            switch self {
            case .oneMB: "≥ 1 MB"
            case .tenMB: "≥ 10 MB"
            case .fiftyMB: "≥ 50 MB"
            case .hundredMB: "≥ 100 MB"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                controlBar

                if isScanning {
                    PalCard {
                        HStack(spacing: 20) {
                            ProgressView().tint(Color.palMint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Scanning for duplicate files…")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Comparing exact byte sizes and calculating SHA-256 stream hashes in \(targetFolderURL.lastPathComponent).")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                        }
                    }
                } else if duplicateGroups.isEmpty {
                    PalCard {
                        HStack(spacing: 20) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.palMint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No Duplicate Files Found")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Click 'Scan Duplicates' to search for identical documents, archives, videos, and duplicate downloads in \(targetFolderURL.lastPathComponent).")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                            Button("Scan Now") {
                                scanDuplicates()
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        }
                    }
                } else {
                    summaryCard
                    duplicatesList
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .quickLookPreview($previewURL)
        .onAppear {
            if duplicateGroups.isEmpty && !isScanning {
                scanDuplicates()
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .top) {
            SectionHeading(
                eyebrow: "Duplicates",
                title: "Universal Duplicate Finder",
                detail: "Locate and reclaim disk space from exact duplicate files, downloads, archives, and documents using multi-stage SHA-256 hashing."
            )
            Spacer()
            Button {
                scanDuplicates()
            } label: {
                Label(isScanning ? "Scanning…" : "Scan Duplicates", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PalButtonStyle(prominent: true))
            .disabled(isScanning)
        }
    }

    private var controlBar: some View {
        PalCard(padding: 14) {
            HStack(spacing: 16) {
                Menu {
                    Button("Downloads") { targetFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"); scanDuplicates() }
                    Button("Documents") { targetFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"); scanDuplicates() }
                    Button("Desktop") { targetFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"); scanDuplicates() }
                    Button("Home Folder (~)") { targetFolderURL = FileManager.default.homeDirectoryForCurrentUser; scanDuplicates() }
                    Divider()
                    Button("Choose Custom Folder…") { chooseFolder() }
                } label: {
                    Label(targetFolderURL.lastPathComponent, systemImage: "folder")
                }
                .buttonStyle(PalButtonStyle())

                Spacer()

                HStack(spacing: 8) {
                    Text("Min Size:")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)

                    Picker("Min Size", selection: $minSizeOption) {
                        ForEach(MinSizeOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: minSizeOption) {
                        scanDuplicates()
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        let totalWasted = duplicateGroups.reduce(0) { $0 + $1.wastedBytes }
        return PalCard(padding: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found \(duplicateGroups.count) Duplicate Sets")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("You can safely reclaim up to \(ByteText.string(totalWasted)) by removing duplicate copies while preserving original files.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()

                Button {
                    copyDuplicateReport()
                } label: {
                    Label(copiedReport ? "Report Copied!" : "Copy Report", systemImage: copiedReport ? "checkmark" : "doc.on.clipboard")
                }
                .buttonStyle(PalButtonStyle())

                Button("Trash All Duplicates (\(ByteText.string(totalWasted)))") {
                    for group in duplicateGroups {
                        cleanDuplicates(in: group)
                    }
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
    }

    private var duplicatesList: some View {
        VStack(spacing: 16) {
            ForEach(duplicateGroups) { group in
                PalCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(group.originalCandidate.name)
                                        .font(.system(size: 14, weight: .bold))
                                    Text("\(group.duplicates.count + 1) copies")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.palMint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.palMint.opacity(0.12), in: Capsule())
                                }
                                Text("\(ByteText.string(group.fileSize)) each  •  Reclaim \(ByteText.string(group.wastedBytes)) by trashing \(group.duplicates.count) duplicate(s)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                            Button("Trash Duplicates") {
                                cleanDuplicates(in: group)
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        }

                        Divider()

                        VStack(spacing: 8) {
                            fileCandidateRow(group.originalCandidate, isOriginal: true)
                            ForEach(group.duplicates) { dupe in
                                fileCandidateRow(dupe, isOriginal: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fileCandidateRow(_ candidate: FileCandidate, isOriginal: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isOriginal ? "checkmark.circle.fill" : "doc.on.doc.fill")
                .foregroundStyle(isOriginal ? Color.palMint : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(candidate.url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                    if isOriginal {
                        Text("ORIGINAL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.palMint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.palMint.opacity(0.12), in: Capsule())
                    }
                }
                Text(candidate.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.palMuted)
                    .lineLimit(1)
            }

            Spacer()

            if let date = candidate.modifiedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                previewURL = candidate.url
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(PalButtonStyle())

            Button {
                model.open(candidate.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(PalButtonStyle())
        }
        .padding(8)
        .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            targetFolderURL = url
            scanDuplicates()
        }
    }

    private func scanDuplicates() {
        isScanning = true
        Task {
            let groups = await duplicateService.scanDuplicates(in: targetFolderURL, minSizeBytes: minSizeOption.rawValue)
            self.duplicateGroups = groups
            self.isScanning = false
        }
    }

    private func cleanDuplicates(in group: DuplicateFileGroup) {
        model.moveBatchToTrash(group.duplicates)
        duplicateGroups.removeAll { $0.id == group.id }
    }

    private func copyDuplicateReport() {
        var lines: [String] = ["Storage Pal - Duplicate File Report", "Target: \(targetFolderURL.path)", ""]
        for group in duplicateGroups {
            lines.append("Duplicate Set: \(group.originalCandidate.name) (\(ByteText.string(group.fileSize)) each)")
            lines.append("  [Original]  \(group.originalCandidate.url.path)")
            for dupe in group.duplicates {
                lines.append("  [Duplicate] \(dupe.url.path)")
            }
            lines.append("")
        }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedReport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            copiedReport = false
        }
    }
}
