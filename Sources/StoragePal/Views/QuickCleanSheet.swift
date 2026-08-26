import SwiftUI

struct QuickCleanSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItemIDs: Set<String> = []
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var isCleaning = false
    @State private var cleaningMessage = "Safely clearing temporary files…"
    @State private var cleanSummary: QuickCleanSummary?

    private var scanResult: QuickCleanScanResult? {
        model.quickCleanScanResult
    }

    private var allItems: [QuickCleanItem] {
        scanResult?.items ?? []
    }

    private var selectedItems: [QuickCleanItem] {
        allItems.filter { selectedItemIDs.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            if isCleaning {
                cleaningView
            } else if let summary = cleanSummary {
                successView(summary: summary)
            } else if model.isQuickCleanScanning {
                scanningView
            } else if allItems.isEmpty {
                cleanStateView
            } else {
                content
                Divider()
                footer
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 580)
        .background(Color.palCream)
        .task {
            if scanResult == nil && !model.isQuickCleanScanning {
                await model.runQuickScan()
            }
            if let result = model.quickCleanScanResult {
                selectedItemIDs = Set(result.items.map { $0.id })
            }
        }
        .onChange(of: model.quickCleanScanResult?.createdAt) {
            if let result = model.quickCleanScanResult {
                selectedItemIDs = Set(result.items.map { $0.id })
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.palMint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.palMint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Quick Scan & Smart Clean")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Low-risk cleanup of temporary caches, stale logs, and leftover clutter.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.palMuted)
            }

            Spacer()

            Button(cleanSummary != nil ? "Done" : "Cancel") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle())
        }
        .padding(20)
    }

    // MARK: - Main Review Content
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Hero Banner
                heroBanner

                // Zero Risk Safety Guarantee Card
                safetyGuaranteeCard

                // Category List
                if let groups = scanResult?.groups {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CATEGORIES READY TO CLEAN (\(groups.count))")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.palMint)
                            Spacer()
                            Button(selectedItemIDs.count == allItems.count ? "Deselect All" : "Select All") {
                                if selectedItemIDs.count == allItems.count {
                                    selectedItemIDs.removeAll()
                                } else {
                                    selectedItemIDs = Set(allItems.map { $0.id })
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.palMint)
                        }

                        ForEach(groups) { group in
                            categoryCard(group: group)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Hero Banner
    private var heroBanner: some View {
        PalCard(padding: 18) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ESTIMATED SAFE SPACE RECOVERY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.palMint)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ByteText.string(selectedBytes))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.palInk)

                        Text("selected to free up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.palMuted)
                    }

                    Text("Across \(selectedItems.count) disposable files, caches, and orphaned folders.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.black.opacity(0.06), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: allItems.isEmpty ? 0 : Double(selectedItems.count) / Double(allItems.count))
                        .stroke(Color.palMint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.palMint)
                }
                .frame(width: 64, height: 64)
            }
        }
    }

    // MARK: - Safety Guarantee Card
    private var safetyGuaranteeCard: some View {
        PalCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.palMint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Zero-Risk Review Guarantee")
                        .font(.system(size: 12, weight: .bold))
                    Text("Personal documents, photos, saved passwords, active logins, and git source repositories are never touched. Items move to Trash where they can be recovered.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
            }
        }
    }

    // MARK: - Category Card
    private func categoryCard(group: QuickCleanCategoryGroup) -> some View {
        let isGroupFullySelected = group.items.allSatisfy { selectedItemIDs.contains($0.id) }
        let isGroupPartiallySelected = group.items.contains { selectedItemIDs.contains($0.id) } && !isGroupFullySelected
        let isExpanded = expandedCategoryIDs.contains(group.id)

        return PalCard(padding: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    // Checkbox
                    Button {
                        if isGroupFullySelected {
                            for item in group.items {
                                selectedItemIDs.remove(item.id)
                            }
                        } else {
                            for item in group.items {
                                selectedItemIDs.insert(item.id)
                            }
                        }
                    } label: {
                        Image(systemName: isGroupFullySelected ? "checkmark.circle.fill" : (isGroupPartiallySelected ? "minus.circle.fill" : "circle"))
                            .font(.system(size: 19))
                            .foregroundStyle(isGroupFullySelected || isGroupPartiallySelected ? group.kind.tint : Color.palMuted)
                    }
                    .buttonStyle(.plain)

                    // Category Icon
                    Image(systemName: group.kind.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(group.kind.tint)
                        .frame(width: 36, height: 36)
                        .background(group.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    // Title & Description
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(group.kind.rawValue)
                                .font(.system(size: 13, weight: .bold))

                            Text(ByteText.string(group.totalBytes))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(group.kind.tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(group.kind.tint.opacity(0.12), in: Capsule())

                            Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.palMuted)
                        }

                        Text(group.kind.safetyDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Expand / Collapse Details Button
                    Button {
                        if isExpanded {
                            expandedCategoryIDs.remove(group.id)
                        } else {
                            expandedCategoryIDs.insert(group.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Hide details" : "Show items")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.palMuted)
                    }
                    .buttonStyle(.plain)
                }

                // Expanded Item List
                if isExpanded {
                    Divider().opacity(0.6)

                    VStack(spacing: 8) {
                        ForEach(group.items) { item in
                            let isItemSelected = selectedItemIDs.contains(item.id)
                            HStack(spacing: 12) {
                                Button {
                                    if isItemSelected {
                                        selectedItemIDs.remove(item.id)
                                    } else {
                                        selectedItemIDs.insert(item.id)
                                    }
                                } label: {
                                    Image(systemName: isItemSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(isItemSelected ? group.kind.tint : Color.palMuted)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(item.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.palMuted)
                                }

                                Spacer()

                                Text(ByteText.string(item.bytes))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.palInk)

                                Button {
                                    model.open(item.url)
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer
    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedItems.count) of \(allItems.count) item(s) selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.palMuted)
                Text("Total: \(ByteText.string(selectedBytes))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.palInk)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle())

            Button {
                performQuickClean()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Clean & Free Up \(ByteText.string(selectedBytes))")
                }
            }
            .buttonStyle(PalButtonStyle(prominent: true))
            .disabled(selectedItems.isEmpty)
        }
        .padding(20)
    }

    // MARK: - In-Progress Cleaning View
    private var cleaningView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(Color.palMint)
                .scaleEffect(1.3)

            VStack(spacing: 6) {
                Text("Freeing Up Storage…")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(cleaningMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.palMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Scanning View
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(Color.palMint)
                .scaleEffect(1.2)

            VStack(spacing: 6) {
                Text("Having a Quick Look…")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Checking temporary caches, stale logs, and orphaned leftovers")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.palMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Clean State View (Nothing Found)
    private var cleanStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.palMint)

            VStack(spacing: 6) {
                Text("Your Mac is Clean & Fresh")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("No temporary caches, stale logs, or orphaned leftovers were found.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.palMuted)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle(prominent: true))
            .padding(.top, 10)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Success View
    private func successView(summary: QuickCleanSummary) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.palMint.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.palMint)
            }

            VStack(spacing: 8) {
                Text("Freed Up \(ByteText.string(summary.reclaimedBytes))!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.palInk)

                Text("Successfully cleaned \(summary.cleanedItemsCount) disposable files and folders.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.palMuted)
            }

            // Summary Breakdown
            PalCard(padding: 16) {
                VStack(spacing: 10) {
                    ForEach(Array(summary.categoryBreakdown.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { kind in
                        if let bytes = summary.categoryBreakdown[kind], bytes > 0 {
                            HStack {
                                Image(systemName: kind.symbol)
                                    .foregroundStyle(kind.tint)
                                    .frame(width: 20)
                                Text(kind.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text(ByteText.string(bytes))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.palMint)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 420)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle(prominent: true))
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // MARK: - Execution Action
    private func performQuickClean() {
        isCleaning = true
        cleaningMessage = "Safely cleaning \(selectedItems.count) items…"

        Task {
            let summary = await model.executeQuickClean(selectedItems: selectedItems)
            self.cleanSummary = summary
            self.isCleaning = false
        }
    }
}
