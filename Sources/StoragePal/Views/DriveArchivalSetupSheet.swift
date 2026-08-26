import SwiftUI
import AppKit

struct DriveArchivalSetupSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let initialDisk: DiskSnapshot?
    let initialPreset: DriveArchivePresetKind

    @State private var selectedDiskID: String = ""
    @State private var customDestinationURL: URL? = nil
    @State private var selectedPreset: DriveArchivePresetKind = .downloadsRelief
    @State private var ruleName: String = ""
    @State private var sourceFolderURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var destinationSubfolder: String = "StoragePal_Archive/Downloads"
    @State private var targetAction: MaintenanceAction = .moveToExternalDrive
    @State private var schedule: MaintenanceSchedule = .weekly
    @State private var minAgeDays: Int = 14
    @State private var minFileBytes: Int64 = 0
    @State private var enableLowSpaceTrigger: Bool = true
    @State private var lowSpaceThresholdGB: Double = 25.0
    @State private var enableFolderSizeTrigger: Bool = false
    @State private var folderSizeLimitGB: Double = 10.0
    @State private var organizeByYearMonth: Bool = true
    @State private var notifyOnExecution: Bool = true
    @State private var isEnabled: Bool = true

    init(disk: DiskSnapshot? = nil, preset: DriveArchivePresetKind = .downloadsRelief) {
        self.initialDisk = disk
        self.initialPreset = preset
    }

    private var externalDisks: [DiskSnapshot] {
        model.report?.externalDisks ?? []
    }

    private var currentTargetDisk: DiskSnapshot? {
        if let disk = externalDisks.first(where: { $0.id == selectedDiskID }) {
            return disk
        }
        return initialDisk ?? externalDisks.first
    }

    private var effectiveDestinationURL: URL? {
        if let custom = customDestinationURL {
            return custom
        }
        guard let disk = currentTargetDisk else { return nil }
        return disk.path.appendingPathComponent(destinationSubfolder, isDirectory: true)
    }

    private var previewRule: MaintenanceRule {
        MaintenanceRule(
            name: ruleName.isEmpty ? "Archive \(sourceFolderURL.lastPathComponent)" : ruleName,
            isEnabled: isEnabled,
            sourceFolderURL: sourceFolderURL,
            targetAction: targetAction,
            destinationFolderURL: effectiveDestinationURL,
            schedule: schedule,
            minAgeDays: minAgeDays,
            minFileBytes: minFileBytes,
            notifyOnExecution: notifyOnExecution,
            enableFolderSizeTrigger: enableFolderSizeTrigger,
            folderSizeLimitGB: folderSizeLimitGB,
            organizeByYearMonth: organizeByYearMonth,
            externalVolumeName: currentTargetDisk?.name
        )
    }

    private var previewResults: (candidates: [FileCandidate], totalBytes: Int64) {
        model.previewRule(previewRule)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preset Selection
                    presetSection

                    // Target External Drive
                    targetDriveSection

                    // Source Folder & Actions
                    sourceAndActionSection

                    // Low-Space & Schedule Triggers
                    triggersSection

                    // Live Matching File Preview
                    livePreviewSection
                }
                .padding(24)
            }

            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 740, minHeight: 600, idealHeight: 680)
        .background(Color.palCream)
        .onAppear {
            if let disk = initialDisk {
                selectedDiskID = disk.id
            } else if let first = externalDisks.first {
                selectedDiskID = first.id
            }
            selectedPreset = initialPreset
            applyPreset(initialPreset)
            lowSpaceThresholdGB = model.lowSpaceConfig.thresholdGB
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.palMint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.palMint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Set up Automated Archiving & Backup")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Automatically offload downloads, old files, or create backups when Mac space is limited.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.palMuted)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle())
        }
        .padding(20)
    }

    // MARK: - Preset Selection Section
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE AN AUTOMATION TEMPLATE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.palMint)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(DriveArchivePresetKind.allCases) { preset in
                    Button {
                        selectedPreset = preset
                        applyPreset(preset)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(selectedPreset == preset ? Color.palMint : Color.palMuted)
                                .frame(width: 32, height: 32)
                                .background((selectedPreset == preset ? Color.palMint : Color.black).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.palInk)
                                Text(preset.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.palMuted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedPreset == preset ? Color.palSidebarSelection : Color.palCardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedPreset == preset ? Color.palMint : Color.palCardBorder, lineWidth: selectedPreset == preset ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Target Drive Section
    private var targetDriveSection: some View {
        PalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("DESTINATION EXTERNAL DRIVE & FOLDER")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.palMint)

                if externalDisks.isEmpty && customDestinationURL == nil {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No external drives currently detected. You can connect a drive via USB/Thunderbolt or pick a custom mounted folder/NAS.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.palMuted)
                        Spacer()
                        Button("Choose Custom Path…") {
                            chooseCustomFolder()
                        }
                        .buttonStyle(PalButtonStyle())
                    }
                } else {
                    HStack(spacing: 12) {
                        Picker("Target Drive:", selection: $selectedDiskID) {
                            ForEach(externalDisks) { disk in
                                Text("\(disk.name) (\(ByteText.string(disk.availableBytes)) free)").tag(disk.id)
                            }
                        }
                        .labelsHidden()

                        Spacer()

                        Button("Choose Custom Folder…") {
                            chooseCustomFolder()
                        }
                        .buttonStyle(PalButtonStyle())
                    }

                    if let dest = effectiveDestinationURL {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.palMint)
                            Text("Will archive to:")
                                .font(.system(size: 11, weight: .semibold))
                            Text(dest.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.palMuted)
                                .lineLimit(1)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - Source & Actions Section
    private var sourceAndActionSection: some View {
        PalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("SOURCE FOLDER & TRANSFER BEHAVIOR")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.palMint)

                // Quick Folder Selection
                HStack(spacing: 8) {
                    Text("Source:")
                        .font(.system(size: 12, weight: .semibold))

                    Button("Downloads") {
                        sourceFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    }
                    .buttonStyle(PalButtonStyle(prominent: sourceFolderURL.lastPathComponent == "Downloads"))

                    Button("Desktop") {
                        sourceFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                    }
                    .buttonStyle(PalButtonStyle(prominent: sourceFolderURL.lastPathComponent == "Desktop"))

                    Button("Documents") {
                        sourceFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
                    }
                    .buttonStyle(PalButtonStyle(prominent: sourceFolderURL.lastPathComponent == "Documents"))

                    Spacer()

                    Button("Choose Other…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            sourceFolderURL = url
                        }
                    }
                    .buttonStyle(PalButtonStyle())
                }

                Divider()

                // Action Type (Move vs Copy)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transfer Action:")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $targetAction) {
                            Text("Move to External Drive (Frees Mac Space)").tag(MaintenanceAction.moveToExternalDrive)
                            Text("Copy to External Drive (Preserves Local Copy)").tag(MaintenanceAction.copyToExternalDrive)
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                // Filters: Age & Size
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Minimum File Age:")
                                .font(.system(size: 12, weight: .semibold))
                            Text(minAgeDays == 0 ? "Any age (all files)" : "Older than \(minAgeDays) days")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.palMint)
                        }
                        Slider(value: Binding(
                            get: { Double(minAgeDays) },
                            set: { minAgeDays = Int($0) }
                        ), in: 0...90, step: 7)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Minimum File Size:")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $minFileBytes) {
                            Text("Any size").tag(Int64(0))
                            Text("> 10 MB").tag(Int64(10_000_000))
                            Text("> 50 MB").tag(Int64(50_000_000))
                            Text("> 100 MB").tag(Int64(100_000_000))
                            Text("> 500 MB").tag(Int64(500_000_000))
                        }
                        .labelsHidden()
                    }
                }

                Toggle("Organize transferred files into YYYY-MM date subfolders automatically", isOn: $organizeByYearMonth)
                    .font(.system(size: 12))
            }
        }
    }

    // MARK: - Triggers & Safeguards Section
    private var triggersSection: some View {
        PalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("AUTOMATED TRIGGERS & SAFEGUARDS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.palMint)

                // Low Storage Trigger
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("⚡ Low-Space Safeguard: Trigger when Mac free storage drops below threshold", isOn: $enableLowSpaceTrigger)
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        if enableLowSpaceTrigger {
                            Text("< \(Int(lowSpaceThresholdGB)) GB free")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    if enableLowSpaceTrigger {
                        HStack(spacing: 12) {
                            Slider(value: $lowSpaceThresholdGB, in: 10...100, step: 5)
                            Text("\(Int(lowSpaceThresholdGB)) GB")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 50, alignment: .trailing)
                        }
                        Text("When available space on this Mac SSD drops below \(Int(lowSpaceThresholdGB)) GB, this rule will automatically run to offload matching files to your external drive.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }
                }

                Divider()

                // Recurring Schedule
                HStack {
                    Text("Recurring Schedule:")
                        .font(.system(size: 12, weight: .semibold))
                    Picker("", selection: $schedule) {
                        ForEach(MaintenanceSchedule.allCases) { sched in
                            Text(sched.title).tag(sched)
                        }
                    }
                    .labelsHidden()

                    Spacer()

                    Toggle("Notify on transfer", isOn: $notifyOnExecution)
                        .font(.system(size: 12))
                }
            }
        }
    }

    // MARK: - Live Preview Section
    private var livePreviewSection: some View {
        PalCard(padding: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.palMint.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.palMint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Match Preview in \(sourceFolderURL.lastPathComponent)")
                        .font(.system(size: 13, weight: .bold))

                    if previewResults.candidates.isEmpty {
                        Text("No files currently match these filters (e.g. all files in \(sourceFolderURL.lastPathComponent) are newer than \(minAgeDays) days).")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    } else {
                        Text("Found \(previewResults.candidates.count) file(s) totaling \(ByteText.string(previewResults.totalBytes)) ready to transfer.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.palMint)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Footer
    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ruleName.isEmpty ? "Automated Archiving Rule" : ruleName)
                    .font(.system(size: 12, weight: .bold))
                Text(targetAction == .moveToExternalDrive ? "Moves files to free Mac SSD space" : "Copies files as a backup")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.palMuted)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle())

            Button {
                saveRule()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("Activate Automated Archiving")
                }
            }
            .buttonStyle(PalButtonStyle(prominent: true))
            .disabled(effectiveDestinationURL == nil)
        }
        .padding(20)
    }

    // MARK: - Actions & Helpers
    private func applyPreset(_ preset: DriveArchivePresetKind) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch preset {
        case .downloadsRelief:
            ruleName = "Auto-Archive Downloads (Space Relief)"
            sourceFolderURL = home.appendingPathComponent("Downloads")
            destinationSubfolder = "StoragePal_Archive/Downloads"
            targetAction = .moveToExternalDrive
            minAgeDays = 14
            minFileBytes = 0
            enableLowSpaceTrigger = true
            schedule = .weekly
            organizeByYearMonth = true

        case .oldUnusedFiles:
            ruleName = "Archive Old & Large Files"
            sourceFolderURL = home.appendingPathComponent("Downloads")
            destinationSubfolder = "StoragePal_Archive/Old_Files"
            targetAction = .moveToExternalDrive
            minAgeDays = 30
            minFileBytes = 50_000_000
            enableLowSpaceTrigger = true
            schedule = .weekly
            organizeByYearMonth = true

        case .documentsBackup:
            ruleName = "Backup Documents to External Drive"
            sourceFolderURL = home.appendingPathComponent("Documents")
            destinationSubfolder = "StoragePal_Backups/Documents"
            targetAction = .copyToExternalDrive
            minAgeDays = 0
            minFileBytes = 0
            enableLowSpaceTrigger = false
            schedule = .weekly
            organizeByYearMonth = false

        case .custom:
            ruleName = "Custom External Archiving Rule"
        }
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Archive Destination"
        if panel.runModal() == .OK, let url = panel.url {
            customDestinationURL = url
        }
    }

    private func saveRule() {
        guard let destination = effectiveDestinationURL else { return }

        // Create destination directory if needed
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let rule = MaintenanceRule(
            name: ruleName.isEmpty ? "\(targetAction == .moveToExternalDrive ? "Archive" : "Backup") \(sourceFolderURL.lastPathComponent)" : ruleName,
            isEnabled: true,
            sourceFolderURL: sourceFolderURL,
            targetAction: targetAction,
            destinationFolderURL: destination,
            schedule: schedule,
            minAgeDays: minAgeDays,
            minFileBytes: minFileBytes,
            notifyOnExecution: notifyOnExecution,
            enableFolderSizeTrigger: enableFolderSizeTrigger,
            folderSizeLimitGB: folderSizeLimitGB,
            organizeByYearMonth: organizeByYearMonth,
            externalVolumeName: currentTargetDisk?.name
        )

        model.addOrUpdateRule(rule)

        if enableLowSpaceTrigger {
            model.lowSpaceConfig.isEnabled = true
            model.lowSpaceConfig.autoExecuteRules = true
            model.lowSpaceConfig.thresholdGB = lowSpaceThresholdGB
            model.saveLowSpaceConfig()
        }

        dismiss()
    }
}
