import SwiftUI

private enum DashboardSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case tidy = "Tidy list"
    case duplicates = "Duplicates"
    case apps = "Apps"
    case startup = "Startup"
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
        case .tidy: "checklist"
        case .duplicates: "doc.on.doc"
        case .apps: "app.badge.checkmark"
        case .startup: "gearshape.2"
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
    @State private var section: DashboardSection = .today
    @State private var isShowingUpdateSheet = false

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
                                isShowingUpdateSheet = true
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
                        case .tidy: TidyListView()
                        case .duplicates: DuplicateFinderView()
                        case .apps: AppUninstallerView()
                        case .startup: StartupManagerView()
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
        .sheet(isPresented: $isShowingUpdateSheet) {
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

            VStack(spacing: 6) {
                ForEach(DashboardSection.allCases) { item in
                    Button {
                        section = item
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

            Spacer()

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
                    Button {
                        model.runScan()
                    } label: {
                        Label("Check again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PalButtonStyle())
                    .disabled(model.isScanning)
                }

                if let report = model.report, let disk = report.internalDisk {
                    permissionBannerIfNeeded(report)
                    healthCard(report: report, disk: disk)
                    forecastCard
                    nextSteps(report)
                } else {
                    welcomeCard
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
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
                        Button("Check my Mac") { model.runScan() }
                            .buttonStyle(PalButtonStyle(prominent: true))
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
