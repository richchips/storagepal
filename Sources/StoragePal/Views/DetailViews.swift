import QuickLook
import SwiftUI

struct TidyListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(
                    eyebrow: "Tidy list",
                    title: "Small wins, in a sensible order",
                    detail: "Nothing happens without you choosing it. Files moved to Trash remain recoverable until you empty it."
                )

                if let report = model.report {
                    let actionable = report.recommendations.filter { $0.kind != .iCloud }
                    if actionable.isEmpty {
                        PalCard {
                            HStack(spacing: 22) {
                                EmptyIllustration()
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("All clear for now")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                    Text("There’s no high-value tidy-up to suggest. Enjoy the breathing room.")
                                        .foregroundStyle(Color.palMuted)
                                }
                            }
                        }
                    } else {
                        ForEach(Array(actionable.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.palInk, in: Circle())
                                    .padding(.top, 17)
                                RecommendationRowDetail(item: item)
                            }
                        }
                    }
                } else {
                    PalCard {
                        HStack {
                            Text(model.isScanning ? model.scanMessage : "Run a check to make your first tidy list.")
                            Spacer()
                            if !model.isScanning {
                                Button("Check my Mac") { model.runScan() }
                                    .buttonStyle(PalButtonStyle(prominent: true))
                            }
                        }
                    }
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct RecommendationRowDetail: View {
    @EnvironmentObject private var model: AppModel
    let item: StorageRecommendation

    var body: some View {
        PalCard(padding: 18) {
            HStack(spacing: 16) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.palMint)
                    .frame(width: 44, height: 44)
                    .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 14, weight: .bold))
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if item.reclaimableBytes > 0 {
                    Text(ByteText.string(item.reclaimableBytes))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.palMint)
                }
                Button(item.actionLabel) { model.handle(item) }
                    .buttonStyle(PalButtonStyle())
            }
        }
    }
}

struct DrivesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(
                    eyebrow: "Drives",
                    title: "Your storage, at a glance",
                    detail: "External archive drives appear automatically when they’re connected."
                )

                if let disks = model.report?.disks, !disks.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(disks) { disk in
                            driveCard(disk)
                        }
                    }
                } else {
                    PalCard {
                        Text(model.isScanning ? model.scanMessage : "Run a check to see your drives.")
                            .foregroundStyle(Color.palMuted)
                    }
                }

                PalCard {
                    HStack(spacing: 16) {
                        Image(systemName: "externaldrive.badge.timemachine")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("A simple archive habit")
                                .font(.system(size: 14, weight: .bold))
                            Text("Move completed projects and old media to an external drive; keep current work local. Keep a second copy of anything irreplaceable.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func driveCard(_ disk: DiskSnapshot) -> some View {
        PalCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: disk.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(disk.isInternal ? Color.palInk : Color.palMint)
                    Spacer()
                    Text(disk.isInternal ? "THIS MAC" : (disk.isRemovable ? "REMOVABLE" : "EXTERNAL"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
                Text(disk.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                StorageBar(usedFraction: disk.usedFraction, tint: disk.usedFraction > 0.9 ? .orange : .palMint)
                HStack {
                    Text("\(ByteText.string(disk.availableBytes)) free")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(ByteText.string(disk.totalBytes))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                Button("Open in Finder") { model.openFolder(disk.path) }
                    .buttonStyle(PalButtonStyle())
            }
        }
    }
}

private enum ICloudTab: String, CaseIterable, Identifiable {
    case folders = "Folders & App Containers"
    case downloaded = "Local SSD Hogs"
    case clutter = "iCloud Clutter & Ghosts"
    case guide = "Untangle Guide"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .folders: "folder.fill"
        case .downloaded: "arrow.down.circle.fill"
        case .clutter: "trash.circle.fill"
        case .guide: "lightbulb.fill"
        }
    }
}

struct ICloudView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: ICloudTab = .folders
    @State private var folderSearchText: String = ""
    @State private var selectedClutterIDs: Set<String> = []
    @State private var expandedFolderPaths: Set<String> = []

    private var report: ICloudUntangleReport {
        model.iCloudReport ?? .empty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header & Action Bar
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "iCloud",
                        title: "iCloud Untangler & Storage Studio",
                        detail: "Inspect every folder and app container, measure local SSD vs cloud storage, evict downloads, and sweep clutter."
                    )
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            model.scanICloudStorage()
                        } label: {
                            if model.isICloudScanning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Scan iCloud", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(PalButtonStyle())
                        .disabled(model.isICloudScanning)

                        if let report = model.iCloudReport, report.totalLocalSSDBytes > 0 {
                            Button {
                                model.evictAllDownloadedICloudFiles()
                            } label: {
                                Label("Evict All Local Downloads", systemImage: "arrow.up.to.line.circle")
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        }
                    }
                }

                // Dual Storage Breakdown Bar
                HStack(alignment: .top, spacing: 14) {
                    PalCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Local SSD Footprint", systemImage: "internaldrive.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.palMint)
                            Text(ByteText.string(report.totalLocalSSDBytes))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("Files taking physical disk space on this Mac")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PalCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Cloud-Only Footprint", systemImage: "icloud.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                            Text(ByteText.string(report.totalEvictedCloudBytes))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("Dataless placeholders (0 bytes on Mac SSD)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PalCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Total iCloud Drive Size", systemImage: "chart.pie.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.palInk)
                            Text(ByteText.string(report.totalICloudBytes))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("\(report.topFolders.count + report.appContainers.count) folders & apps tracked")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Tab Selector
                Picker("", selection: $selectedTab) {
                    ForEach(ICloudTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                // Tab Content
                switch selectedTab {
                case .folders:
                    folderExplorerSection
                case .downloaded:
                    downloadedFilesSection
                case .clutter:
                    clutterSection
                case .guide:
                    untangleGuideSection
                }
            }
            .padding(30)
            .frame(maxWidth: 950, alignment: .leading)
        }
        .onAppear {
            if model.iCloudReport == nil {
                model.scanICloudStorage()
            }
        }
    }

    // MARK: - Tab 1: Folders & App Containers Explorer

    private var folderExplorerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("iCloud Folders & Application Containers")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                TextField("Search folders or apps…", text: $folderSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            let allFolders = (report.topFolders + report.appContainers).filter {
                folderSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(folderSearchText) || ($0.appIdentifier?.localizedCaseInsensitiveContains(folderSearchText) == true)
            }

            if allFolders.isEmpty {
                PalCard {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.palMint)
                        Text(model.isICloudScanning ? "Scanning iCloud folders…" : "No matching folders found.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.palMuted)
                    }
                }
            } else {
                ForEach(allFolders) { folder in
                    folderCard(folder)
                }
            }
        }
    }

    private func folderCard(_ folder: ICloudFolderNode) -> some View {
        let isExpanded = expandedFolderPaths.contains(folder.id)

        return PalCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: folder.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(folder.isAppContainer ? .purple : Color.palMint)
                        .frame(width: 38, height: 38)
                        .background((folder.isAppContainer ? Color.purple : Color.palMint).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(folder.name)
                                .font(.system(size: 13, weight: .bold))

                            if folder.isAppContainer {
                                Text("App Container")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }

                        Text("\(ByteText.string(folder.totalLogicalBytes)) total  •  \(folder.fileCount) files  •  \(ByteText.string(folder.localPhysicalBytes)) downloaded on Mac")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }

                    Spacer()

                    // Action buttons
                    if folder.localPhysicalBytes > 0 {
                        Button {
                            model.evictICloudFolder(folder)
                        } label: {
                            Label("Evict Folder", systemImage: "arrow.up.to.line")
                        }
                        .buttonStyle(PalButtonStyle())
                        .help("Removes local downloads for all files in this folder while preserving them safely in iCloud.")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .buttonStyle(PalButtonStyle())
                    .help("Reveal folder in Finder")

                    Button {
                        if isExpanded {
                            expandedFolderPaths.remove(folder.id)
                        } else {
                            expandedFolderPaths.insert(folder.id)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Split Bar (Local vs Cloud)
                if folder.totalLogicalBytes > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.palMint)
                                .frame(width: geo.size.width * CGFloat(folder.localFraction))
                            Rectangle()
                                .fill(Color.blue.opacity(0.4))
                                .frame(width: geo.size.width * CGFloat(1.0 - folder.localFraction))
                        }
                    }
                    .frame(height: 5)
                    .clipShape(Capsule())
                }

                // Expanded Largest Files
                if isExpanded && !folder.largestFiles.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Largest Files in this Folder:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.palMuted)

                        ForEach(folder.largestFiles) { file in
                            HStack(spacing: 8) {
                                Image(systemName: file.isDownloadedLocally ? "icloud.and.arrow.down.fill" : "icloud")
                                    .font(.system(size: 11))
                                    .foregroundStyle(file.isDownloadedLocally ? Color.palMint : .blue)
                                Text(file.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text(ByteText.string(file.bytes))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.palMuted)

                                if file.isDownloadedLocally {
                                    Button("Evict") {
                                        model.evictFromLocalSSD(
                                            FileCandidate(
                                                id: file.url.path,
                                                url: file.url,
                                                bytes: file.bytes,
                                                modifiedAt: file.modifiedAt,
                                                isCloudItem: true
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.palMint)
                                } else {
                                    Button("Download") {
                                        model.downloadICloudFile(file)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.blue)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Tab 2: Downloaded Local SSD Files

    private var downloadedFilesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloaded Files Stored on Mac SSD (\(report.downloadedFiles.count))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("These files take physical disk space on your Mac. Evicting frees local SSD space immediately while keeping the file stored safely in iCloud.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()
                if !report.downloadedFiles.isEmpty {
                    Button("Evict All Downloaded Files") {
                        model.evictAllDownloadedICloudFiles()
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                }
            }

            if report.downloadedFiles.isEmpty {
                PalCard {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Heavy Downloaded Files on SSD")
                                .font(.system(size: 13, weight: .bold))
                            Text("All iCloud files are currently offloaded/dataless in the cloud, using 0 bytes of local SSD space.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                ForEach(report.downloadedFiles.prefix(30)) { file in
                    PalCard(padding: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "icloud.and.arrow.down.fill")
                                .foregroundStyle(Color.palMint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.system(size: 12, weight: .bold))
                                Text("\(ByteText.string(file.bytes))  •  \(file.category)  •  \(file.url.deletingLastPathComponent().lastPathComponent)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.palMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button("Evict to Cloud") {
                                model.evictFromLocalSSD(
                                    FileCandidate(
                                        id: file.url.path,
                                        url: file.url,
                                        bytes: file.bytes,
                                        modifiedAt: file.modifiedAt,
                                        isCloudItem: true
                                    )
                                )
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 3: iCloud Clutter & Ghost Apps

    private var clutterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Clutter & Ghost App Containers (\(report.clutterCandidates.count))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Uninstalled app containers, legacy archives (.dmg/.pkg/.zip), and sync conflict duplicates taking up space in your iCloud account.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()

                if !selectedClutterIDs.isEmpty {
                    Button("Move Selected to Trash (\(selectedClutterIDs.count))") {
                        let selectedItems = report.clutterCandidates.filter { selectedClutterIDs.contains($0.id) }
                        model.trashICloudClutter(items: selectedItems)
                        selectedClutterIDs.removeAll()
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                }
            }

            if report.clutterCandidates.isEmpty {
                PalCard {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zero iCloud Clutter Detected")
                                .font(.system(size: 13, weight: .bold))
                            Text("No abandoned app folders, sync conflicts, or stale archives were found in iCloud Drive.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                ForEach(report.clutterCandidates) { item in
                    PalCard(padding: 12) {
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { selectedClutterIDs.contains(item.id) },
                                set: { isOn in
                                    if isOn { selectedClutterIDs.insert(item.id) } else { selectedClutterIDs.remove(item.id) }
                                }
                            ))
                            .labelsHidden()

                            Image(systemName: item.kind.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(item.kind.color)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .bold))
                                    Text(item.kind.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(item.kind.color.opacity(0.12), in: Capsule())
                                        .foregroundStyle(item.kind.color)
                                }
                                Text("\(ByteText.string(item.bytes))  •  \(item.reason)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.palMuted)
                            }

                            Spacer()

                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(PalButtonStyle())
                            .help("Reveal in Finder")

                            Button("Trash") {
                                model.trashICloudClutter(items: [item])
                            }
                            .buttonStyle(PalButtonStyle())
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 4: Untangle Guide

    private var untangleGuideSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PalCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The Least-Effort Order to Untangle iCloud")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    cloudStep(
                        number: 1,
                        title: "Use “Evict Folder” or “Evict All” for instant local Mac relief",
                        detail: "Evicting marks files as dataless on your Mac SSD. They remain 100% accessible in iCloud Drive and download automatically when opened."
                    )

                    cloudStep(
                        number: 2,
                        title: "Sweep Ghost App Containers & Stale Archives",
                        detail: "When you uninstall an app from your Mac, its iCloud data container remains in Apple's cloud indefinitely. Storage Pal identifies these ghost folders so you can safely trash them."
                    )

                    cloudStep(
                        number: 3,
                        title: "Empty iCloud Recently Deleted",
                        detail: "Deleted files in iCloud Drive and Photos continue consuming cloud storage for up to 30 days. Open Apple's panel to permanently purge recently deleted items."
                    )
                }
            }

            PalCard {
                HStack(spacing: 14) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.palInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple iCloud Account Quota")
                            .font(.system(size: 13, weight: .bold))
                        Text("Apple manages device backups, iCloud Photos, Mail, and Messages directly. Use Apple's panel for total account quota management.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }
                    Spacer()
                    Button("Manage Apple ID Settings…") {
                        model.openICloudSettings()
                    }
                    .buttonStyle(PalButtonStyle())
                }
            }
        }
    }

    private func cloudStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(Color.palMint, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.palMuted)
            }
        }
    }
}

private enum FileCategoryFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "All"
    case videos = "Videos"
    case pictures = "Pictures"
    case archives = "Archives"
    case documents = "Documents"

    var id: String { rawValue }

    func matches(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .all: return true
        case .videos: return ["mov", "mp4", "m4v", "mkv", "avi"].contains(ext)
        case .pictures: return ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff"].contains(ext)
        case .archives: return ["zip", "dmg", "pkg", "tar", "gz", "rar", "7z"].contains(ext)
        case .documents: return ["pdf", "doc", "docx", "txt", "pages", "numbers", "key", "csv"].contains(ext)
        }
    }
}

private enum FileSortOption: String, CaseIterable, Identifiable, Hashable {
    case sizeDescending = "Largest"
    case sizeAscending = "Smallest"
    case dateDescending = "Newest"
    case nameAscending = "Name A-Z"

    var id: String { rawValue }
    var title: String { rawValue }
}

struct FileReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let recommendation: StorageRecommendation

    @State private var selectedCandidateIDs: Set<String> = []
    @State private var pendingTrash: FileCandidate?
    @State private var confirmBatchTrash = false
    @State private var previewURL: URL?
    @State private var searchText = ""
    @State private var categoryFilter: FileCategoryFilter = .all
    @State private var sortOption: FileSortOption = .sizeDescending

    private var filteredCandidates: [FileCandidate] {
        var items = recommendation.candidates

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = searchText.lowercased()
            items = items.filter { $0.name.lowercased().contains(query) || $0.url.path.lowercased().contains(query) }
        }

        items = items.filter { categoryFilter.matches($0.url) }

        switch sortOption {
        case .sizeDescending:
            items.sort { $0.bytes > $1.bytes }
        case .sizeAscending:
            items.sort { $0.bytes < $1.bytes }
        case .dateDescending:
            items.sort { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        case .nameAscending:
            items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        return items
    }

    private var selectedCandidates: [FileCandidate] {
        recommendation.candidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    private var allFilteredSelected: Bool {
        let filteredIDs = Set(filteredCandidates.map { $0.id })
        return !filteredIDs.isEmpty && filteredIDs.isSubset(of: selectedCandidateIDs)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            controlsBar
            Divider()

            if filteredCandidates.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.palMuted)
                    Text("No matching files found")
                        .font(.system(size: 16, weight: .bold))
                    Text("Try adjusting your search or category filter.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.palMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                candidateList
            }
        }
        .frame(minWidth: 840, minHeight: 580)
        .background(Color.palCream)
        .quickLookPreview($previewURL)
        .alert("Move to Trash?", isPresented: Binding(
            get: { pendingTrash != nil },
            set: { if !$0 { pendingTrash = nil } }
        ), presenting: pendingTrash) { candidate in
            Button("Cancel", role: .cancel) { pendingTrash = nil }
            Button("Move to Trash", role: .destructive) {
                model.moveToTrash(candidate)
                selectedCandidateIDs.remove(candidate.id)
                pendingTrash = nil
            }
        } message: { candidate in
            if candidate.isCloudItem {
                Text("“\(candidate.name)” is in iCloud. Moving it to Trash removes it from iCloud and synced devices, though it remains recoverable until Trash is emptied.")
            } else {
                Text("“\(candidate.name)” will remain recoverable until you empty the Trash.")
            }
        }
        .alert("Move \(selectedCandidates.count) items to Trash?", isPresented: $confirmBatchTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                let toTrash = selectedCandidates
                selectedCandidateIDs.removeAll()
                model.moveBatchToTrash(toTrash)
            }
        } message: {
            let totalBytes = selectedCandidates.reduce(0) { $0 + $1.bytes }
            Text("This will move \(selectedCandidates.count) files (\(ByteText.string(totalBytes))) to Trash. Items remain recoverable until Trash is emptied.")
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text(recommendation.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PalButtonStyle(prominent: true))
        }
        .padding(20)
    }

    private var controlsBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search files…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 8))

                Picker("Sort", selection: $sortOption) {
                    ForEach(FileSortOption.allCases, id: \.self) { (option: FileSortOption) in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            HStack(spacing: 10) {
                Button {
                    let filteredIDs = Set(filteredCandidates.map { $0.id })
                    if allFilteredSelected {
                        selectedCandidateIDs.subtract(filteredIDs)
                    } else {
                        selectedCandidateIDs.formUnion(filteredIDs)
                    }
                } label: {
                    Label(allFilteredSelected ? "Deselect All" : "Select All (\(filteredCandidates.count))",
                          systemImage: allFilteredSelected ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(PalButtonStyle())

                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FileCategoryFilter.allCases) { cat in
                            Button(cat.rawValue) {
                                categoryFilter = cat
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(categoryFilter == cat ? Color.palMint : Color.black.opacity(0.06), in: Capsule())
                            .foregroundStyle(categoryFilter == cat ? .white : Color.palInk)
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !selectedCandidateIDs.isEmpty {
                    if !(model.report?.externalDisks.isEmpty ?? true) {
                        Button("Archive (\(selectedCandidates.count))") {
                            let toArchive = selectedCandidates
                            selectedCandidateIDs.removeAll()
                            model.archiveBatch(toArchive)
                        }
                        .buttonStyle(PalButtonStyle())
                    }
                    Button("Trash (\(selectedCandidates.count))") {
                        confirmBatchTrash = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.palSidebarBackground.opacity(0.5))
    }

    private var candidateList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredCandidates) { candidate in
                    let isSelected = selectedCandidateIDs.contains(candidate.id)
                    HStack(spacing: 14) {
                        Button {
                            if isSelected {
                                selectedCandidateIDs.remove(candidate.id)
                            } else {
                                selectedCandidateIDs.insert(candidate.id)
                            }
                        } label: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(isSelected ? Color.palMint : Color.palMuted)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: icon(for: candidate.url))
                            .font(.system(size: 18))
                            .foregroundStyle(Color.palMint)
                            .frame(width: 40, height: 40)
                            .background(Color.palMint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(ByteText.string(candidate.bytes))
                                if let date = candidate.modifiedAt {
                                    Text("•")
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            Text(candidate.url.deletingLastPathComponent().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            previewURL = candidate.url
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }
                        .buttonStyle(PalButtonStyle())

                        Button("Show") { model.open(candidate.url) }
                            .buttonStyle(PalButtonStyle())

                        if !(model.report?.externalDisks.isEmpty ?? true) {
                            Button("Archive…") { model.archive(candidate) }
                                .buttonStyle(PalButtonStyle())
                        }

                        if ["mov", "mp4", "m4v", "avi", "pdf"].contains(candidate.url.pathExtension.lowercased()) {
                            Button("Compress") {
                                model.compressMedia(candidate)
                            }
                            .buttonStyle(PalButtonStyle())
                            .help("Compress media/PDF file")
                        }

                        Button("Trash") { pendingTrash = candidate }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    .padding(14)
                    .background(isSelected ? Color.palMint.opacity(0.08) : Color.palRowBackground, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.palMint.opacity(0.4), lineWidth: 1.5)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi": "film"
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff": "photo"
        case "zip", "dmg", "pkg", "tar", "gz", "rar", "7z": "shippingbox"
        case "pdf", "doc", "docx", "txt", "pages", "numbers", "key": "doc.richtext"
        default: "doc"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var clipboardGuard = ClipboardGuardService.shared
    @ObservedObject private var updateService = AppUpdateService.shared

    var body: some View {
        Form {
            Section("Checks") {
                Picker("Check storage", selection: Binding(
                    get: { model.scanFrequency },
                    set: { model.scanFrequency = $0 }
                )) {
                    ForEach(ScanFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                Toggle("Notify me only when space needs attention", isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { model.notificationsEnabled = $0 }
                ))
                Toggle("Launch Storage Pal at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section("Software Updates") {
                Toggle("Automatically check for updates", isOn: $updateService.automaticallyCheckForUpdates)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Storage Pal v\(updateService.currentVersion)")
                            .font(.system(size: 12, weight: .bold))
                        if let lastCheck = updateService.lastCheckDate {
                            Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Check for Updates Now") {
                        Task {
                            await updateService.checkForUpdates(userInitiated: true)
                        }
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                }
                .padding(.vertical, 2)
            }

            Section("Clipboard & AI Privacy Guard") {
                Toggle("Proactive Clipboard PII Guard", isOn: $clipboardGuard.isEnabled)
                Text("Monitors copied text for API keys (OpenAI, Anthropic, AWS, GitHub), private keys, and credit cards, offering 1-click clipboard sanitization or Pal Vault encryption.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Permissions & Access") {
                HStack(spacing: 12) {
                    Image(systemName: model.hasFullDiskAccess ? "checkmark.seal.fill" : "lock.trianglebadge.exclamationmark.fill")
                        .foregroundStyle(model.hasFullDiskAccess ? Color.palMint : .orange)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasFullDiskAccess ? "Full Disk Access Granted" : "Full Disk Access Recommended")
                            .font(.system(size: 13, weight: .bold))
                        Text(model.hasFullDiskAccess ? "Storage Pal can cleanly inspect and remove protected app containers and caches." : "Enables removing sandboxed app containers in ~/Library/Containers and system files.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.hasFullDiskAccess ? "Open Settings" : "Grant Access") {
                        model.openFullDiskAccessSettings()
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Button("Full Disk Access Settings") { model.openFullDiskAccessSettings() }
                    Button("Files & Folders") { model.openFilesAndFoldersSettings() }
                    Button("macOS Storage") { model.openStorageSettings() }
                }
            }

            Section("Safety") {
                Label("Storage Pal never deletes files automatically.", systemImage: "checkmark.shield")
                Label("Moving a file to Trash always requires confirmation.", systemImage: "trash.slash")
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .sheet(isPresented: $updateService.isPresented) {
            AppUpdateSheet()
        }
    }
}
