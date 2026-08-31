import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case pulse = "Pulse"
    case tidy = "Tidy list"
    case duplicates = "Duplicates"
    case apps = "Apps"
    case startup = "Startup"
    case activity = "Activity"
    case updates = "Updates"
    case photos = "Photos"
    case vault = "Vault"
    case sanitize = "Sanitize"
    case consolidate = "Consolidate"
    case localHub = "Own Your Data"
    case treemap = "Treemap"
    case drives = "Drives"
    case iCloud = "iCloud"
    case automation = "Automate"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .pulse: "waveform.path.ecg"
        case .tidy: "checklist"
        case .duplicates: "doc.on.doc"
        case .apps: "app.badge.checkmark"
        case .startup: "gearshape.2"
        case .activity: "waveform.path"
        case .updates: "arrow.triangle.2.circlepath"
        case .photos: "photo.stack"
        case .vault: "lock.shield.fill"
        case .sanitize: "location.slash.fill"
        case .consolidate: "externaldrive.badge.plus"
        case .localHub: "banknote.fill"
        case .treemap: "square.split.2x2"
        case .drives: "externaldrive"
        case .iCloud: "icloud"
        case .automation: "bolt.horizontal.circle"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var clipboardGuard = ClipboardGuardService.shared
    @ObservedObject private var updateService = AppUpdateService.shared
    private var section: DashboardSection { model.dashboardSection }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.45)
            ZStack {
                LinearGradient(
                    colors: [Color.palCream, Color.palMist.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if case .updateAvailable(let release) = updateService.status {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.palMint)
                            Text("Storage Pal v\(release.version) is now available.")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button("What's New & Update…") {
                                updateService.isPresented = true
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.palMint.opacity(0.12))
                        Divider()
                    }
                    if let clipItem = clipboardGuard.detectedSensitiveItem {
                        HStack(spacing: 12) {
                            Image(systemName: clipItem.kind.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Clipboard Secret Detected:")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(clipItem.kind.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.red)
                                    Text("(\(clipItem.snippet))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.palMuted)
                                }
                            }
                            Spacer()
                            Button("Sanitize Clipboard") {
                                clipboardGuard.sanitizeClipboard()
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))

                            Button("Encrypt to Vault") {
                                clipboardGuard.encryptToVault()
                            }
                            .buttonStyle(PalButtonStyle())

                            Button {
                                clipboardGuard.dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.12))
                        Divider()
                    }
                    if let error = model.errorMessage {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 12))
                                .lineLimit(2)
                            Spacer()
                            Button("Copy Error Details") {
                                model.copyActiveError()
                            }
                            .buttonStyle(PalButtonStyle())
                            Button {
                                model.errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.12))
                        Divider()
                    }

                    Group {
                        switch section {
                        case .today: TodayView()
                        case .pulse: PulseView()
                        case .tidy: TidyListView()
                        case .duplicates: DuplicateFinderView()
                        case .apps: AppUninstallerView()
                        case .startup: StartupManagerView()
                        case .activity: PulseActivityView()
                        case .updates: PulseUpdatesView()
                        case .photos: PhotoDeduplicatorView()
                        case .vault: PalVaultView()
                        case .sanitize: ConfidentialSanitizerView()
                        case .consolidate: DriveConsolidatorView()
                        case .localHub: LocalArchivalHubView()
                        case .treemap: TreemapView()
                        case .drives: DrivesView()
                        case .iCloud: ICloudView()
                        case .automation: AutomationView()
                        }
                    }
                }
            }
        }
        .background(Color.palCream)
        .sheet(item: $model.selectedRecommendation) { recommendation in
            FileReviewView(recommendation: recommendation)
                .environmentObject(model)
        }
        .sheet(item: $model.permissionRecoveryContext) { context in
            PermissionRecoverySheet(context: context)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isBrowserCleanerViewPresented) {
            BrowserCleanerView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isQuickCleanSheetPresented) {
            QuickCleanSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $updateService.isPresented) {
            AppUpdateSheet()
        }
        .alert("Storage Pal", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Something went wrong.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.palInk)
                        .frame(width: 38, height: 38)
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Storage Pal")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("A calmer Mac")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(DashboardSection.allCases) { item in
                        Button {
                            model.dashboardSection = item
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol)
                                    .frame(width: 20)
                                Text(item.rawValue)
                                Spacer()
                                if item == .tidy,
                                   let count = model.report?.recommendations.filter({ $0.kind != .iCloud }).count,
                                   count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.palMint.opacity(0.16), in: Capsule())
                                }
                            }
                            .font(.system(size: 13, weight: section == item ? .semibold : .medium))
                            .foregroundStyle(section == item ? Color.palInk : Color.palMuted)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(section == item ? Color.palSidebarSelection : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            VStack(alignment: .leading, spacing: 9) {
                Label(model.isScanning ? model.scanMessage : lastCheckedText, systemImage: model.isScanning ? "arrow.triangle.2.circlepath" : "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button(model.isScanning ? "Pause check" : "Check now") {
                    model.isScanning ? model.cancelScan() : model.runScan()
                }
                .buttonStyle(PalButtonStyle())
            }
            .padding(20)
        }
        .frame(width: 220)
        .background(Color.palSidebarBackground)
    }

    private var lastCheckedText: String {
        guard let date = model.report?.createdAt ?? model.lastScanDate else { return "Not checked yet" }
        return "Checked \(date.formatted(.relative(presentation: .named)))"
    }
}

private struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Today",
                        title: greeting,
                        detail: "One clear view of what needs attention — and what doesn’t."
                    )
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            model.dashboardSection = .pulse
                        } label: {
                            Label("Pulse", systemImage: "waveform.path.ecg")
                        }
                        .buttonStyle(PalButtonStyle())
                        Button {
                            Task {
                                await model.runQuickScan()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if model.isQuickCleanScanning {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(model.isQuickCleanScanning ? "Scanning…" : "Quick Scan")
                            }
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))
                        .disabled(model.isQuickCleanScanning || model.isInlineQuickCleaning)

                        Button {
                            model.runScan()
                        } label: {
                            Label("Full Check", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(PalButtonStyle())
                        .disabled(model.isScanning)
                    }
                }

                if let report = model.report, let disk = report.internalDisk {
                    permissionBannerIfNeeded(report)
                    healthCard(report: report, disk: disk)
                    TodayQuickScanSection()
                    forecastCard
                    nextSteps(report)
                } else {
                    welcomeCard
                    TodayQuickScanSection()
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .task {
            if model.quickCleanScanResult == nil && !model.isQuickCleanScanning {
                await model.runQuickScan()
            }
        }
    }

    @ObservedObject private var sentinel = StorageSentinelService.shared

    @ViewBuilder
    private var forecastCard: some View {
        if let forecast = sentinel.currentForecast {
            PalCard(padding: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.palMint)
                        .frame(width: 40, height: 40)
                        .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("STORAGE VELOCITY & FORECAST")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.palMint)
                        HStack(spacing: 8) {
                            Text(forecast.velocityStatus)
                                .font(.system(size: 13, weight: .bold))
                            if let days = forecast.estimatedDaysRemaining {
                                Text("~\(days) days remaining")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                        if let spike = forecast.runawayFolderSpike {
                            Text(spike)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        } else {
                            Text("No runaway log or cache spikes detected in background.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func permissionBannerIfNeeded(_ report: ScanReport) -> some View {
        if !report.skippedLocations.isEmpty {
            PalCard(padding: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Some locations couldn’t be checked")
                            .font(.system(size: 13, weight: .bold))
                        Text("macOS permission boundaries prevented checking \(report.skippedLocations.count) location(s). Grant access in Privacy & Security to include all locations.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }
                    Spacer()
                    Button("Privacy & Security") {
                        model.openPrivacySettings()
                    }
                    .buttonStyle(PalButtonStyle())
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var welcomeCard: some View {
        PalCard {
            HStack(spacing: 30) {
                EmptyIllustration()
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.isScanning ? "Having a gentle look…" : "Let’s find some breathing room")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    Text(model.isScanning ? model.scanMessage : "Storage Pal checks the usual clutter spots and turns them into a short, safe tidy list.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.palMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isScanning {
                        ProgressView().tint(Color.palMint).frame(width: 220)
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await model.runQuickScan()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("Quick Scan")
                                }
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))

                            Button("Check my Mac") { model.runScan() }
                                .buttonStyle(PalButtonStyle())
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private func healthCard(report: ScanReport, disk: DiskSnapshot) -> some View {
        PalCard(padding: 28) {
            HStack(spacing: 34) {
                ZStack {
                    Circle().stroke(Color.black.opacity(0.07), lineWidth: 13)
                    Circle()
                        .trim(from: 0, to: min(max(disk.usedFraction, 0.025), 1))
                        .stroke(report.health.tint, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(ByteText.string(disk.availableBytes))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("free")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 138, height: 138)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Mac storage status: \(report.health.title)")
                .accessibilityValue("\(ByteText.string(disk.availableBytes)) free of \(ByteText.string(disk.totalBytes)) total")

                VStack(alignment: .leading, spacing: 13) {
                    Label(report.health.title, systemImage: report.health == .calm ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(report.health.tint)
                    Text(healthHeadline(report.health))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.palInk)
                    Text(healthDetail(report: report))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.palMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    StorageBar(usedFraction: disk.usedFraction, tint: report.health.tint)
                    HStack {
                        Text("\(ByteText.string(disk.usedBytes)) used")
                        Spacer()
                        Text("\(ByteText.string(disk.totalBytes)) total")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func nextSteps(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("The helpful next steps")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                if report.potentialSavings > 0 {
                    Text("Up to \(ByteText.string(report.potentialSavings)) to review")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.palMint)
                }
            }

            let items = Array(report.recommendations.filter { $0.kind != .archive }.prefix(3))
            if items.isEmpty {
                PalCard {
                    Label("Nothing pressing. Storage Pal will keep an eye on things.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.palMint)
                }
            } else {
                ForEach(items) { item in
                    RecommendationRow(item: item)
                }
            }
        }
    }

    private func healthHeadline(_ health: StorageHealth) -> String {
        switch health {
        case .calm: "You have room to breathe."
        case .watch: "A small tidy will help."
        case .urgent: "Let’s free up space today."
        }
    }

    private func healthDetail(report: ScanReport) -> String {
        switch report.health {
        case .calm: "No big cleanup needed. Review a suggestion only if you feel like it."
        case .watch: "Storage Pal found \(report.recommendations.count) manageable places to start."
        case .urgent: "Start with the first suggestion. You can stop after one useful action."
        }
    }
}

private struct RecommendationRow: View {
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title).font(.system(size: 14, weight: .bold))
                        if item.reclaimableBytes > 0 {
                            Text(ByteText.string(item.reclaimableBytes))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.palMint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.palMint.opacity(0.11), in: Capsule())
                        }
                        if item.confidenceScore >= 0.70 {
                            HStack(spacing: 3) {
                                Image(systemName: "brain.head.profile")
                                Text(item.confidencePercentageText)
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                        .lineLimit(2)
                }
                Spacer()
                Button(item.actionLabel) { model.handle(item) }
                    .buttonStyle(PalButtonStyle())
            }
        }
    }
}

private struct TodayQuickScanSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var deselectedItemIDs: Set<String> = []

    private var scanResult: QuickCleanScanResult? {
        model.quickCleanScanResult
    }

    private var allItems: [QuickCleanItem] {
        scanResult?.items ?? []
    }

    private var selectedItems: [QuickCleanItem] {
        allItems.filter { !deselectedItemIDs.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isInlineQuickCleaning {
                cleaningCard
            } else if let summary = model.lastQuickCleanSummary {
                summaryCard(summary: summary)
            } else if model.isQuickCleanScanning {
                scanningCard
            } else if let result = scanResult {
                if result.items.isEmpty {
                    cleanFreshCard
                } else {
                    resultsCard(result: result)
                }
            } else {
                readyToScanCard
            }
        }
    }

    // Ready to scan state card
    private var readyToScanCard: some View {
        PalCard(padding: 18) {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.palMint.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.palMint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Quick Scan & Smart Clean")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Low Risk")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.palMint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.palMint.opacity(0.12), in: Capsule())
                    }
                    Text("Intelligently scans disposable browser web caches, stale crash dumps, build artifacts, and orphaned app leftovers.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()

                Button {
                    Task {
                        await model.runQuickScan()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Quick Scan Now")
                    }
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
    }

    // Scanning in progress card
    private var scanningCard: some View {
        PalCard(padding: 18) {
            HStack(spacing: 16) {
                ProgressView()
                    .tint(Color.palMint)
                    .scaleEffect(1.1)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Intelligent Quick Scan in progress…")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(model.quickCleanScanMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()
            }
        }
    }

    // Cleaning in progress card
    private var cleaningCard: some View {
        PalCard(padding: 18) {
            HStack(spacing: 16) {
                ProgressView()
                    .tint(Color.palMint)
                    .scaleEffect(1.1)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Safely Freeing Up Storage…")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Clearing temporary files and safely moving clutter to Trash.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()
            }
        }
    }

    // Post-clean summary card
    private func summaryCard(summary: QuickCleanSummary) -> some View {
        PalCard(padding: 18) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.palMint.opacity(0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.palMint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Freed Up \(ByteText.string(summary.reclaimedBytes))!")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.palInk)
                        Text("Cleaned \(summary.cleanedItemsCount) items")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.palMint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.palMint.opacity(0.12), in: Capsule())
                    }
                    Text("All cleaned items were safely cleared or placed in Trash.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Scan Again") {
                        model.lastQuickCleanSummary = nil
                        Task {
                            await model.runQuickScan()
                        }
                    }
                    .buttonStyle(PalButtonStyle())

                    Button("Dismiss") {
                        model.lastQuickCleanSummary = nil
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                }
            }
        }
    }

    // Clean / Fresh state card
    private var cleanFreshCard: some View {
        PalCard(padding: 18) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.palMint.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.palMint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Mac is Clean & Fresh")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("No temporary caches, stale crash dumps, or orphaned residue found.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()

                Button("Scan Again") {
                    Task {
                        await model.runQuickScan()
                    }
                }
                .buttonStyle(PalButtonStyle())
            }
        }
    }

    // Discovered results card
    private func resultsCard(result: QuickCleanScanResult) -> some View {
        PalCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                // Header row
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.palMint.opacity(0.16))
                            .frame(width: 48, height: 48)
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.palMint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Quick Scan Found \(ByteText.string(selectedBytes))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.palInk)
                            Text("Ready to Clean")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.palMint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.palMint.opacity(0.12), in: Capsule())
                        }
                        Text("\(selectedItems.count) disposable files and folders selected. 100% safe to remove.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.palMuted)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await model.performInlineQuickClean(items: selectedItems)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Clean & Free Up (\(ByteText.string(selectedBytes)))")
                            }
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))
                        .disabled(selectedItems.isEmpty)

                        Button {
                            model.isQuickCleanSheetPresented = true
                        } label: {
                            Text("Detailed Review…")
                        }
                        .buttonStyle(PalButtonStyle())

                        Button {
                            Task {
                                await model.runQuickScan()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(PalButtonStyle())
                        .help("Rescan Quick Targets")
                    }
                }

                Divider().opacity(0.5)

                // Itemized Category Breakdown
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("WHAT QUICK SCAN FOUND (\(result.groups.count) CATEGORIES)")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.palMint)
                        Spacer()
                        Text("Click Inspect to see individual items")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }

                    ForEach(result.groups) { group in
                        categoryRow(group: group)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMint)
                    Text("Zero-Risk Guarantee: Documents, photos, git repositories, cookies, and saved passwords are never touched.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
                .padding(.top, 4)
            }
        }
    }

    private func categoryRow(group: QuickCleanCategoryGroup) -> some View {
        let isExpanded = expandedCategoryIDs.contains(group.id)
        let groupSelectedItems = group.items.filter { !deselectedItemIDs.contains($0.id) }
        let isFullySelected = groupSelectedItems.count == group.items.count
        let isPartiallySelected = !groupSelectedItems.isEmpty && !isFullySelected

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Category Checkbox
                Button {
                    if isFullySelected {
                        for item in group.items {
                            deselectedItemIDs.insert(item.id)
                        }
                    } else {
                        for item in group.items {
                            deselectedItemIDs.remove(item.id)
                        }
                    }
                } label: {
                    Image(systemName: isFullySelected ? "checkmark.circle.fill" : (isPartiallySelected ? "minus.circle.fill" : "circle"))
                        .font(.system(size: 17))
                        .foregroundStyle(isFullySelected || isPartiallySelected ? group.kind.tint : Color.palMuted)
                }
                .buttonStyle(.plain)

                // Category Icon
                Image(systemName: group.kind.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(group.kind.tint)
                    .frame(width: 30, height: 30)
                    .background(group.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                // Title & Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.kind.rawValue)
                            .font(.system(size: 13, weight: .bold))
                        Text("(\(group.items.count))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }
                    Text(group.kind.safetyDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.palMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text(ByteText.string(group.totalBytes))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.palInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(group.kind.tint.opacity(0.10), in: Capsule())

                // Expand / Collapse
                Button {
                    if isExpanded {
                        expandedCategoryIDs.remove(group.id)
                    } else {
                        expandedCategoryIDs.insert(group.id)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide" : "Inspect")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.palMint)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(group.items) { item in
                        let isSelected = !deselectedItemIDs.contains(item.id)
                        HStack(spacing: 10) {
                            Button {
                                if isSelected {
                                    deselectedItemIDs.insert(item.id)
                                } else {
                                    deselectedItemIDs.remove(item.id)
                                }
                            } label: {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(isSelected ? group.kind.tint : Color.palMuted)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.palMuted)
                            }

                            Spacer()

                            Text(ByteText.string(item.bytes))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.palInk)

                            Button {
                                model.open(item.url)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Color.black.opacity(0.015), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}
