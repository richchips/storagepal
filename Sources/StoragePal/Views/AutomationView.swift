import SwiftUI

struct AutomationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingRule: MaintenanceRule?
    @State private var isCreatingNewRule = false
    @State private var previewingRule: MaintenanceRule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(
                    eyebrow: "Automate",
                    title: "Hands-off storage maintenance",
                    detail: "Set schedules to clean or archive folders automatically, and trigger actions when storage gets low."
                )

                lowSpaceCard
                rulesHeader
                rulesList
                logSection
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditSheet(rule: rule) { updatedRule in
                model.addOrUpdateRule(updatedRule)
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $isCreatingNewRule) {
            RuleEditSheet(rule: nil) { newRule in
                model.addOrUpdateRule(newRule)
            }
            .environmentObject(model)
        }
        .sheet(item: $previewingRule) { rule in
            RulePreviewSheet(rule: rule)
                .environmentObject(model)
        }
    }

    private var lowSpaceCard: some View {
        PalCard(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Low Storage Trigger", systemImage: "gauge.badge.plus")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.palInk)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.lowSpaceConfig.isEnabled },
                        set: {
                            model.lowSpaceConfig.isEnabled = $0
                            model.saveLowSpaceConfig()
                        }
                    ))
                    .toggleStyle(.switch)
                }

                Text("Automatically alert or run active rules when available space on your Mac drops below your threshold.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.palMuted)

                if model.lowSpaceConfig.isEnabled {
                    Divider()
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FREE SPACE THRESHOLD")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.palMint)
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { model.lowSpaceConfig.thresholdGB },
                                        set: {
                                            model.lowSpaceConfig.thresholdGB = $0
                                            model.saveLowSpaceConfig()
                                        }
                                    ),
                                    in: 10...100,
                                    step: 5
                                )
                                Text("\(Int(model.lowSpaceConfig.thresholdGB)) GB")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 55, alignment: .trailing)
                            }
                        }

                        Divider().frame(height: 38)

                        Toggle("Auto-execute active rules when low", isOn: Binding(
                            get: { model.lowSpaceConfig.autoExecuteRules },
                            set: {
                                model.lowSpaceConfig.autoExecuteRules = $0
                                model.saveLowSpaceConfig()
                            }
                        ))
                        .font(.system(size: 12, weight: .medium))
                    }
                }
            }
        }
    }

    private var rulesHeader: some View {
        HStack {
            Text("Maintenance Rules")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Spacer()
            Button {
                isCreatingNewRule = true
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(PalButtonStyle(prominent: true))
        }
    }

    private var rulesList: some View {
        VStack(spacing: 12) {
            if model.maintenanceRules.isEmpty {
                PalCard {
                    HStack(spacing: 16) {
                        Image(systemName: "tray.badge.plus")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No maintenance rules set")
                                .font(.system(size: 14, weight: .bold))
                            Text("Create a rule to move old downloads to Trash or archive large folders on a recurring schedule.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                ForEach(model.maintenanceRules) { rule in
                    ruleCard(rule)
                }
            }
        }
    }

    private func ruleCard(_ rule: MaintenanceRule) -> some View {
        PalCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in model.toggleRule(rule) }
                    ))
                    .toggleStyle(.switch)

                    Image(systemName: rule.targetAction.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.palMint)
                        .frame(width: 36, height: 36)
                        .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(rule.name)
                                .font(.system(size: 14, weight: .bold))

                            // Trigger 1: Schedule Badge
                            Text(rule.schedule.title)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.palMint.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.palMint)

                            // Trigger 2: Folder Size Trigger Badge
                            if rule.enableFolderSizeTrigger {
                                Text("Size Trigger: > \(Int(rule.folderSizeLimitGB)) GB")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }

                        HStack(spacing: 6) {
                            Text("Source: \(rule.sourceFolderName)")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(destinationSummary(for: rule))
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                    }

                    Spacer()

                    Button("Preview") {
                        previewingRule = rule
                    }
                    .buttonStyle(PalButtonStyle())

                    Button("Run Now") {
                        model.executeRule(rule)
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))

                    Button {
                        editingRule = rule
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(PalButtonStyle())
                    .help("Edit rule")

                    Button {
                        model.deleteRule(rule)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Delete rule")
                }

                Divider()

                HStack(spacing: 16) {
                    Label(rule.minAgeDays > 0 ? "Older than \(rule.minAgeDays) days" : "Any age", systemImage: "clock")
                    Label(rule.minFileBytes > 0 ? ">= \(ByteText.string(rule.minFileBytes))" : "Any size", systemImage: "arrow.up.left.and.arrow.down.right")
                    if rule.organizeByYearMonth && rule.targetAction != .moveToTrash {
                        Label("Year-Month folders (YYYY-MM)", systemImage: "calendar")
                    }
                    if let lastRun = rule.lastRunDate {
                        Spacer()
                        Text("Last run: \(lastRun.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func destinationSummary(for rule: MaintenanceRule) -> String {
        switch rule.targetAction {
        case .moveToTrash:
            return "macOS Trash"
        case .moveToExternalDrive, .copyToExternalDrive, .archiveToFolder:
            if let dest = rule.destinationFolderURL {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                return dest.path.replacingOccurrences(of: home, with: "~")
            }
            return rule.targetAction.title
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Execution Log")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                if !model.maintenanceLogs.isEmpty {
                    Button("Copy Execution Log") {
                        let lines = model.maintenanceLogs.map { "\($0.timestamp.ISO8601Format()) | \($0.ruleName) | \($0.actionDescription) | \($0.errorDetails ?? "OK")" }
                        let text = lines.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(PalButtonStyle())
                }
            }

            if model.maintenanceLogs.isEmpty {
                Text("No maintenance executions recorded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.palMuted)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.maintenanceLogs.prefix(10))) { log in
                        PalCard(padding: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: log.errorDetails != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(log.errorDetails != nil ? .orange : Color.palMint)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(log.ruleName).fontWeight(.bold)
                                        if let reason = log.triggerReason {
                                            Text(reason.displayLabel)
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.palMint.opacity(0.18), in: Capsule())
                                                .foregroundStyle(Color.palMint)
                                        } else if log.wasTriggeredByLowSpace {
                                            Text("LOW STORAGE TRIGGER")
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.2), in: Capsule())
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Text(log.actionDescription)
                                        .foregroundStyle(Color.palMuted)
                                    if let err = log.errorDetails {
                                        Text(err)
                                            .foregroundStyle(.red)
                                    }
                                }
                                .font(.system(size: 11))

                                Spacer()

                                Text(log.timestamp.formatted(date: .numeric, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RuleEditSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let rule: MaintenanceRule?
    let onSave: (MaintenanceRule) -> Void

    @State private var name: String = ""
    @State private var sourceFolderURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var targetAction: MaintenanceAction = .moveToExternalDrive
    @State private var destinationFolderURL: URL? = nil
    @State private var schedule: MaintenanceSchedule = .weekly
    @State private var minAgeDays: Int = 14
    @State private var minFileBytes: Int64 = 0
    @State private var notifyOnExecution: Bool = true
    @State private var isEnabled: Bool = true
    @State private var enableFolderSizeTrigger: Bool = true
    @State private var folderSizeLimitGB: Double = 10.0
    @State private var organizeByYearMonth: Bool = true
    @State private var externalVolumeName: String? = nil
    @State private var currentSourceFolderSize: Int64 = 0

    init(rule: MaintenanceRule?, onSave: @escaping (MaintenanceRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        if let rule {
            _name = State(initialValue: rule.name)
            _sourceFolderURL = State(initialValue: rule.sourceFolderURL)
            _targetAction = State(initialValue: rule.targetAction)
            _destinationFolderURL = State(initialValue: rule.destinationFolderURL)
            _schedule = State(initialValue: rule.schedule)
            _minAgeDays = State(initialValue: rule.minAgeDays)
            _minFileBytes = State(initialValue: rule.minFileBytes)
            _notifyOnExecution = State(initialValue: rule.notifyOnExecution)
            _isEnabled = State(initialValue: rule.isEnabled)
            _enableFolderSizeTrigger = State(initialValue: rule.enableFolderSizeTrigger)
            _folderSizeLimitGB = State(initialValue: rule.folderSizeLimitGB)
            _organizeByYearMonth = State(initialValue: rule.organizeByYearMonth)
            _externalVolumeName = State(initialValue: rule.externalVolumeName)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rule == nil ? "New Automated Maintenance Rule" : "Edit Maintenance Rule")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PalButtonStyle())
                Button("Save") {
                    let newRule = MaintenanceRule(
                        id: rule?.id ?? UUID().uuidString,
                        name: name.isEmpty ? "Move \(sourceFolderURL.lastPathComponent) to External Drive" : name,
                        isEnabled: isEnabled,
                        sourceFolderURL: sourceFolderURL,
                        targetAction: targetAction,
                        destinationFolderURL: destinationFolderURL,
                        schedule: schedule,
                        minAgeDays: minAgeDays,
                        minFileBytes: minFileBytes,
                        notifyOnExecution: notifyOnExecution,
                        lastRunDate: rule?.lastRunDate,
                        enableFolderSizeTrigger: enableFolderSizeTrigger,
                        folderSizeLimitGB: folderSizeLimitGB,
                        organizeByYearMonth: organizeByYearMonth,
                        externalVolumeName: externalVolumeName
                    )
                    onSave(newRule)
                    dismiss()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
            .padding(20)
            Divider()

            Form {
                Section("Rule Name & Status") {
                    TextField("Rule Name (e.g. Move Downloads to External Drive)", text: $name)
                    Toggle("Rule Active & Running", isOn: $isEnabled)
                }

                Section("Source Folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button("Downloads") {
                                sourceFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                                updateSourceFolderSize()
                            }
                            .buttonStyle(PalButtonStyle(prominent: sourceFolderURL.lastPathComponent == "Downloads"))

                            Button("Desktop") {
                                sourceFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                                updateSourceFolderSize()
                            }
                            .buttonStyle(PalButtonStyle(prominent: sourceFolderURL.lastPathComponent == "Desktop"))

                            Button("Documents") {
                                sourceFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
                                updateSourceFolderSize()
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
                                    updateSourceFolderSize()
                                }
                            }
                            .buttonStyle(PalButtonStyle())
                        }

                        HStack {
                            Text(sourceFolderURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Current size: \(ByteText.string(currentSourceFolderSize))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.palMint)
                        }
                    }
                }

                Section("Target Action & Destination Drive") {
                    Picker("Action", selection: $targetAction) {
                        ForEach(MaintenanceAction.allCases) { action in
                            Label(action.title, systemImage: action.icon).tag(action)
                        }
                    }

                    if targetAction == .moveToExternalDrive || targetAction == .copyToExternalDrive || targetAction == .archiveToFolder {
                        let externalVolumes = model.getMountedExternalVolumes()

                        if !externalVolumes.isEmpty && (targetAction == .moveToExternalDrive || targetAction == .copyToExternalDrive) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Select Connected External Volume:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.palMuted)

                                ForEach(externalVolumes, id: \.path) { vol in
                                    HStack {
                                        Image(systemName: "externaldrive.fill")
                                            .foregroundStyle(Color.palMint)
                                        Text(vol.name)
                                            .font(.system(size: 12, weight: .semibold))
                                        Spacer()
                                        Text("\(ByteText.string(vol.freeBytes)) free of \(ByteText.string(vol.totalBytes))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.palMuted)
                                        Button(destinationFolderURL?.path.hasPrefix(vol.path) == true ? "Selected" : "Select Drive") {
                                            destinationFolderURL = URL(fileURLWithPath: vol.path).appendingPathComponent("StoragePal_Archive/\(sourceFolderURL.lastPathComponent)")
                                            externalVolumeName = vol.name
                                        }
                                        .buttonStyle(PalButtonStyle(prominent: destinationFolderURL?.path.hasPrefix(vol.path) == true))
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Destination Folder:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.palMuted)
                                Text(destinationFolderURL?.path ?? "No destination selected")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Choose Destination Folder…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.prompt = "Select Target Folder"
                                if panel.runModal() == .OK, let url = panel.url {
                                    destinationFolderURL = url
                                    externalVolumeName = url.pathComponents.count > 2 ? url.pathComponents[2] : nil
                                }
                            }
                        }

                        Toggle("Organize moved files into Year-Month subfolders (e.g. 2026-08/)", isOn: $organizeByYearMonth)
                    }
                }

                Section("Dual Automation Triggers") {
                    VStack(alignment: .leading, spacing: 10) {
                        // Trigger 1: Schedule
                        Picker("1. Time Schedule", selection: $schedule) {
                            ForEach(MaintenanceSchedule.allCases) { sched in
                                Text(sched.title).tag(sched)
                            }
                        }

                        Divider()

                        // Trigger 2: Folder Size Threshold
                        Toggle("2. Trigger when Source Folder exceeds size limit", isOn: $enableFolderSizeTrigger)

                        if enableFolderSizeTrigger {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Folder Size Limit: \(Int(folderSizeLimitGB)) GB")
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                    Text(currentSourceFolderSize >= Int64(folderSizeLimitGB * 1_000_000_000) ? "Limit Exceeded (Will Trigger)" : "Within Limit")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(currentSourceFolderSize >= Int64(folderSizeLimitGB * 1_000_000_000) ? .orange : Color.palMint)
                                }

                                Slider(value: $folderSizeLimitGB, in: 2...100, step: 2)
                                Text("Whenever \(sourceFolderURL.lastPathComponent) grows beyond \(Int(folderSizeLimitGB)) GB, files will be transferred to your destination drive.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.palMuted)
                            }
                            .padding(.leading, 8)
                        }
                    }
                }

                Section("File Filters") {
                    Stepper("Only items older than \(minAgeDays) days", value: $minAgeDays, in: 0...365, step: 5)
                    Picker("Minimum File Size", selection: $minFileBytes) {
                        Text("Any size").tag(Int64(0))
                        Text(">= 10 MB").tag(Int64(10_000_000))
                        Text(">= 50 MB").tag(Int64(50_000_000))
                        Text(">= 100 MB").tag(Int64(100_000_000))
                        Text(">= 500 MB").tag(Int64(500_000_000))
                        Text(">= 1 GB").tag(Int64(1_000_000_000))
                    }
                }

                Section("Notifications") {
                    Toggle("Notify me with summary when automation runs", isOn: $notifyOnExecution)
                }
            }
            .formStyle(.grouped)
            .padding(12)
        }
        .frame(minWidth: 580, minHeight: 620)
        .background(Color.palCream)
        .onAppear {
            updateSourceFolderSize()
        }
    }

    private func updateSourceFolderSize() {
        Task {
            let size = model.calculateFolderSize(url: sourceFolderURL)
            self.currentSourceFolderSize = size
        }
    }
}

private struct RulePreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let rule: MaintenanceRule

    var body: some View {
        let (candidates, totalBytes) = model.previewRule(rule)

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dry Run Preview: \(rule.name)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Matching \(candidates.count) files (\(ByteText.string(totalBytes))) in \(rule.sourceFolderName)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PalButtonStyle(prominent: true))
            }
            .padding(20)
            Divider()

            if candidates.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.palMint)
                    Text("No files currently match this rule’s criteria.")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(candidates) { candidate in
                            HStack(spacing: 12) {
                                Image(systemName: "doc")
                                    .foregroundStyle(Color.palMint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text("\(ByteText.string(candidate.bytes))  •  \(candidate.url.path)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.palMuted)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack {
                Spacer()
                if !candidates.isEmpty {
                    Button("Run Rule Now (\(candidates.count) files)") {
                        model.executeRule(rule)
                        dismiss()
                    }
                    .buttonStyle(PalButtonStyle())
                }
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(Color.palCream)
    }
}
