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

struct ICloudView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(
                    eyebrow: "iCloud",
                    title: "Untangle local and cloud storage",
                    detail: "Two different meters can be full: space on your Mac, and your 50 GB iCloud account."
                )

                HStack(alignment: .top, spacing: 16) {
                    PalCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("On this Mac", systemImage: "macbook")
                                .font(.system(size: 13, weight: .bold))
                            Text(model.report?.iCloudFolder.map { ByteText.string($0.bytes) } ?? "—")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("Accessible local files in iCloud Drive")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.palMuted)
                            if let folder = model.report?.iCloudFolder {
                                Button("Open iCloud Drive") { model.openFolder(folder.url) }
                                    .buttonStyle(PalButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    PalCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("In your account", systemImage: "icloud")
                                .font(.system(size: 13, weight: .bold))
                            Text("50 GB plan")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("Apple’s panel includes Photos, backups, Mail, Messages, and app data.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.palMuted)
                            Button("Manage iCloud Storage") { model.openICloudSettings() }
                                .buttonStyle(PalButtonStyle(prominent: true))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                PalCard {
                    VStack(alignment: .leading, spacing: 17) {
                        Text("The least-effort order")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        cloudStep(number: 1, title: "Open Apple’s storage breakdown", detail: "Check whether Photos, device backups, Drive, Mail, or Messages is actually using the space.")
                        cloudStep(number: 2, title: "Empty Recently Deleted", detail: "Deleted iCloud Drive files and Photos can continue using cloud storage for up to 30 days.")
                        cloudStep(number: 3, title: "Use “Remove Download” for local relief", detail: "In Finder, Control-click an iCloud file and choose Remove Download. It stays in iCloud but frees local Mac space.")
                    }
                }

                if !model.localICloudCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Downloaded Local iCloud Files (\(model.localICloudCandidates.count))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("These files are stored locally on your Mac's SSD. Click 'Evict to Cloud' to instantly reclaim local space while preserving the file in iCloud.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.palMuted)

                        ForEach(model.localICloudCandidates) { item in
                            PalCard(padding: 14) {
                                HStack(spacing: 14) {
                                    Image(systemName: "icloud.and.arrow.down")
                                        .foregroundStyle(Color.palMint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.system(size: 13, weight: .bold))
                                        Text("\(ByteText.string(item.bytes))  •  \(item.url.path)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.palMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Evict to Cloud") {
                                        model.evictFromLocalSSD(item)
                                    }
                                    .buttonStyle(PalButtonStyle(prominent: true))
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                    Text("Apple does not give third-party Mac apps access to your complete iCloud quota meter. Storage Pal opens the authoritative Apple panel instead of guessing.")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onAppear {
            model.scanLocalICloudCandidates()
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
