import QuickLook
import SwiftUI

struct PhotoDeduplicatorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: PhotoQualityKind = .duplicates
    @State private var duplicateGroups: [PhotoDuplicateGroup] = []
    @State private var qualityItems: [PhotoQualityItem] = []
    @State private var isScanning = false
    @State private var previewURL: URL?
    @State private var selectedItemIDs: Set<String> = []

    private let deduplicator = PhotoDeduplicatorService()
    private let qualityService = PhotoQualityService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Photos & Media",
                        title: headerTitle,
                        detail: headerDetail
                    )
                    Spacer()
                    Button {
                        scanActiveTab()
                    } label: {
                        Label(isScanning ? "Analyzing…" : "Scan Library", systemImage: "sparkles")
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                    .disabled(isScanning)
                }

                Picker("Photo Category", selection: $selectedTab) {
                    ForEach(PhotoQualityKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTab) {
                    scanActiveTab()
                }

                if isScanning {
                    PalCard {
                        HStack(spacing: 20) {
                            ProgressView().tint(Color.palMint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Analyzing media library…")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Running on-device Apple Vision and image intelligence checks.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                        }
                    }
                } else {
                    switch selectedTab {
                    case .duplicates:
                        duplicatesSection
                    case .screenshot, .blurryOrDark:
                        qualityItemsSection
                    }
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .quickLookPreview($previewURL)
        .onAppear {
            scanActiveTab()
        }
    }

    private var headerTitle: String {
        switch selectedTab {
        case .duplicates: return "Visual Photo Twin Detector"
        case .screenshot: return "Screenshots Sweeper"
        case .blurryOrDark: return "Low Quality & Blur Inspector"
        }
    }

    private var headerDetail: String {
        switch selectedTab {
        case .duplicates:
            return "Find near-identical photos, resized duplicates, and burst shots using on-device Apple Vision machine learning."
        case .screenshot:
            return "Review and remove accumulated screenshots on Desktop and Downloads older than 7 days."
        case .blurryOrDark:
            return "Identify low-resolution accidental thumbnails or out-of-focus captures taking up storage."
        }
    }

    // MARK: - Duplicates Section

    private var duplicatesSection: some View {
        Group {
            if duplicateGroups.isEmpty {
                PalCard {
                    HStack(spacing: 20) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Photo Duplicates Found")
                                .font(.system(size: 15, weight: .bold))
                            Text("Click 'Scan Library' to analyze your pictures for visually identical copies or burst shots.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                let totalWasted = duplicateGroups.reduce(0) { $0 + $1.wastedBytes }
                PalCard(padding: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Found \(duplicateGroups.count) Duplicate Groups")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("You can safely reclaim up to \(ByteText.string(totalWasted)) by keeping the highest resolution copy of each photo.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.palMuted)
                        }
                        Spacer()
                        Button("Clean All Duplicates (\(ByteText.string(totalWasted)))") {
                            for group in duplicateGroups {
                                cleanDuplicates(in: group)
                            }
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))
                    }
                }

                duplicateList
            }
        }
    }

    private var duplicateList: some View {
        VStack(spacing: 16) {
            ForEach(duplicateGroups) { group in
                PalCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(group.bestCandidate.name)
                                        .font(.system(size: 14, weight: .bold))
                                    Text("\(group.duplicates.count + 1) copies")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.palMint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.palMint.opacity(0.12), in: Capsule())
                                }
                                Text("Reclaim \(ByteText.string(group.wastedBytes)) by trashing lower quality duplicates")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                            Button("Keep Best & Trash Duplicates") {
                                cleanDuplicates(in: group)
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        }

                        Divider()

                        HStack(spacing: 14) {
                            photoThumbnail(group.bestCandidate, isBest: true)
                            ForEach(group.duplicates) { dupe in
                                photoThumbnail(dupe, isBest: false)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quality Items (Screenshots & Blur)

    private var qualityItemsSection: some View {
        Group {
            if qualityItems.isEmpty {
                PalCard {
                    HStack(spacing: 20) {
                        Image(systemName: selectedTab.symbol)
                            .font(.system(size: 28))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("All Clear")
                                .font(.system(size: 15, weight: .bold))
                            Text("No \(selectedTab.rawValue.lowercased()) found meeting the cleanup threshold.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                let totalBytes = qualityItems.reduce(0) { $0 + $1.bytes }
                let selectedBytes = qualityItems
                    .filter { selectedItemIDs.contains($0.id) }
                    .reduce(0) { $0 + $1.bytes }

                PalCard(padding: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(qualityItems.count) \(selectedTab.rawValue) (\(ByteText.string(totalBytes)))")
                                .font(.system(size: 14, weight: .bold))
                            Text("Select items to move to Trash.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                        Spacer()
                        Button(selectedItemIDs.count == qualityItems.count ? "Deselect All" : "Select All") {
                            if selectedItemIDs.count == qualityItems.count {
                                selectedItemIDs.removeAll()
                            } else {
                                selectedItemIDs = Set(qualityItems.map { $0.id })
                            }
                        }
                        .buttonStyle(PalButtonStyle())

                        Button("Trash Selected (\(ByteText.string(selectedBytes)))") {
                            trashSelectedQualityItems()
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))
                        .disabled(selectedItemIDs.isEmpty)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    ForEach(qualityItems) { item in
                        let isSelected = selectedItemIDs.contains(item.id)
                        PalCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    if let nsImage = NSImage(contentsOf: item.url) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 110)
                                            .clipped()
                                            .cornerRadius(8)
                                    } else {
                                        Rectangle()
                                            .fill(Color.palRowBackground)
                                            .frame(height: 110)
                                            .cornerRadius(8)
                                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                                    }

                                    Button {
                                        if isSelected {
                                            selectedItemIDs.remove(item.id)
                                        } else {
                                            selectedItemIDs.insert(item.id)
                                        }
                                    } label: {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(isSelected ? Color.palMint : Color.white.opacity(0.8))
                                            .background(Circle().fill(Color.black.opacity(0.35)))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 11, weight: .bold))
                                        .lineLimit(1)
                                    Text(ByteText.string(item.bytes))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.palMint)
                                    Text(item.reason)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.palMuted)
                                        .lineLimit(1)
                                }

                                HStack {
                                    Button {
                                        previewURL = item.url
                                    } label: {
                                        Image(systemName: "eye")
                                    }
                                    .buttonStyle(PalButtonStyle())

                                    Button {
                                        model.open(item.url)
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(PalButtonStyle())

                                    Spacer()

                                    Button {
                                        let candidate = FileCandidate(
                                            id: item.id,
                                            url: item.url,
                                            bytes: item.bytes,
                                            modifiedAt: item.createdAt,
                                            isCloudItem: false
                                        )
                                        model.moveToTrash(candidate)
                                        qualityItems.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func photoThumbnail(_ candidate: FileCandidate, isBest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let nsImage = NSImage(contentsOf: candidate.url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 110, height: 110)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.palRowBackground)
                        .frame(width: 110, height: 110)
                        .cornerRadius(8)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }

                if isBest {
                    Text("KEEP")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.palMint, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(ByteText.string(candidate.bytes))
                    .font(.system(size: 11, weight: .bold))
                Text(candidate.url.pathExtension.uppercased())
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Button {
                previewURL = candidate.url
            } label: {
                Label("Preview", systemImage: "eye")
                    .font(.system(size: 10))
            }
            .buttonStyle(PalButtonStyle())
        }
    }

    private func cleanDuplicates(in group: PhotoDuplicateGroup) {
        model.moveBatchToTrash(group.duplicates)
        duplicateGroups.removeAll { $0.id == group.id }
    }

    private func trashSelectedQualityItems() {
        let targets = qualityItems.filter { selectedItemIDs.contains($0.id) }
        let candidates = targets.map {
            FileCandidate(id: $0.id, url: $0.url, bytes: $0.bytes, modifiedAt: $0.createdAt, isCloudItem: false)
        }
        model.moveBatchToTrash(candidates)
        qualityItems.removeAll { selectedItemIDs.contains($0.id) }
        selectedItemIDs.removeAll()
    }

    private func scanActiveTab() {
        isScanning = true
        Task {
            switch selectedTab {
            case .duplicates:
                let groups = await deduplicator.findDuplicates()
                self.duplicateGroups = groups
            case .screenshot:
                let items = await qualityService.scanScreenshots()
                self.qualityItems = items
                self.selectedItemIDs = Set(items.map { $0.id })
            case .blurryOrDark:
                let items = await qualityService.scanLowQualityPhotos()
                self.qualityItems = items
                self.selectedItemIDs = Set(items.map { $0.id })
            }
            self.isScanning = false
        }
    }
}
