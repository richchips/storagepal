import QuickLook
import SwiftUI

@MainActor
struct DriveConsolidatorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sourceFolders: [URL] = []
    @State private var duplicateGroups: [CrossVolumeDuplicateGroup] = []
    @State private var isScanning = false
    @State private var previewURL: URL?
    @State private var consolidationPlan: DriveConsolidationPlan?

    private let consolidator = DriveConsolidatorService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Consolidate",
                        title: "Universal Drive Consolidator",
                        detail: "Find duplicate files scattered across multiple external USB drives and consolidate them into a single clean archive."
                    )
                    Spacer()
                }

                // Source selection card
                sourceSelectionCard

                if isScanning {
                    PalCard {
                        HStack(spacing: 20) {
                            ProgressView().tint(Color.palMint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Analyzing drives & hashing candidate files…")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Comparing file signatures across all selected storage volumes.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                        }
                    }
                } else if !duplicateGroups.isEmpty {
                    summaryCard
                    duplicatesList
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .quickLookPreview($previewURL)
        .onAppear {
            if sourceFolders.isEmpty {
                // Add default Downloads and Desktop to start with
                let home = FileManager.default.homeDirectoryForCurrentUser
                sourceFolders = [
                    home.appendingPathComponent("Downloads"),
                    home.appendingPathComponent("Pictures")
                ]
            }
        }
    }

    private var sourceSelectionCard: some View {
        PalCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SELECTED VOLUMES & FOLDERS (\(sourceFolders.count))")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.palMint)

                    Spacer()

                    Button {
                        chooseFolder()
                    } label: {
                        Label("Add Drive / Folder…", systemImage: "plus")
                    }
                    .buttonStyle(PalButtonStyle())
                }

                VStack(spacing: 8) {
                    ForEach(sourceFolders, id: \.self) { folder in
                        HStack(spacing: 12) {
                            Image(systemName: isExternalVolume(folder) ? "externaldrive.fill" : "folder.fill")
                                .foregroundStyle(isExternalVolume(folder) ? Color.palMint : Color.palMuted)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.lastPathComponent)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                sourceFolders.removeAll { $0 == folder }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        startScan()
                    } label: {
                        Label("Scan for Cross-Drive Duplicates", systemImage: "sparkles")
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                    .disabled(sourceFolders.count < 2 || isScanning)
                }
            }
        }
    }

    private var summaryCard: some View {
        let totalWasted = duplicateGroups.reduce(0) { $0 + $1.wastedBytes }
        return PalCard(padding: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Found \(duplicateGroups.count) Cross-Drive Duplicate Groups")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("\(ByteText.string(totalWasted)) of identical duplicates scattered across your selected drives.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()

                Button("Clean Redundant Copies (\(ByteText.string(totalWasted)))") {
                    cleanAllRedundantCopies()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
    }

    private var duplicatesList: some View {
        VStack(spacing: 12) {
            ForEach(duplicateGroups) { group in
                PalCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(group.fileName)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(ByteText.string(group.size))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.palMint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.palMint.opacity(0.12), in: Capsule())
                                }
                                Text("\(group.entries.count) copies across drives (Wasting \(ByteText.string(group.wastedBytes)))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.palMuted)
                            }

                            Spacer()

                            Button {
                                if let first = group.entries.first {
                                    previewURL = first.url
                                }
                            } label: {
                                Label("Preview", systemImage: "eye")
                            }
                            .buttonStyle(PalButtonStyle())
                        }

                        Divider()

                        // Locations breakdown
                        VStack(spacing: 6) {
                            ForEach(group.entries) { entry in
                                HStack(spacing: 10) {
                                    Text(entry.volumeName)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.palMuted.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                                    Text(entry.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.palMuted)
                                        .lineLimit(1)

                                    Spacer()

                                    Button("Show") {
                                        model.open(entry.url)
                                    }
                                    .buttonStyle(PalButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Select Volume or Folder"
        if panel.runModal() == .OK {
            for url in panel.urls where !sourceFolders.contains(url) {
                sourceFolders.append(url)
            }
        }
    }

    private func startScan() {
        isScanning = true
        Task {
            let groups = await consolidator.scanCrossVolumeDuplicates(directories: sourceFolders)
            self.duplicateGroups = groups
            self.isScanning = false
        }
    }

    private func isExternalVolume(_ url: URL) -> Bool {
        url.path.hasPrefix("/Volumes/") && !url.path.hasPrefix("/Volumes/Macintosh HD")
    }

    private func cleanAllRedundantCopies() {
        var filesToTrash: [FileCandidate] = []
        for group in duplicateGroups {
            // Keep first, trash subsequent entries
            for entry in group.entries.dropFirst() {
                filesToTrash.append(
                    FileCandidate(
                        id: entry.id,
                        url: entry.url,
                        bytes: entry.size,
                        modifiedAt: entry.modifiedDate,
                        isCloudItem: false
                    )
                )
            }
        }
        model.moveBatchToTrash(filesToTrash)
        duplicateGroups.removeAll()
    }
}
