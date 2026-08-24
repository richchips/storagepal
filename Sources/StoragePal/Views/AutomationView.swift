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

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(rule.name)
                                .font(.system(size: 14, weight: .bold))
                            Text(rule.schedule.title)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.palMint.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.palMint)
                        }

                        Text("Source: \(rule.sourceFolderName)  •  \(rule.targetAction.title)")
                            .font(.system(size: 12))
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
                    .buttonStyle(PalButtonStyle())

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

                HStack(spacing: 16) {
                    Label(rule.minAgeDays > 0 ? "Older than \(rule.minAgeDays) days" : "Any age", systemImage: "clock")
                    Label(rule.minFileBytes > 0 ? ">= \(ByteText.string(rule.minFileBytes))" : "Any size", systemImage: "arrow.up.left.and.arrow.down.right")
                    if let lastRun = rule.lastRunDate {
                        Spacer()
                        Text("Last run: \(lastRun.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
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
                                        if log.wasTriggeredByLowSpace {
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
    @State private var targetAction: MaintenanceAction = .moveToTrash
    @State private var destinationFolderURL: URL? = nil
    @State private var schedule: MaintenanceSchedule = .weekly
    @State private var minAgeDays: Int = 30
    @State private var minFileBytes: Int64 = 100_000_000
    @State private var notifyOnExecution: Bool = true
    @State private var isEnabled: Bool = true

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
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rule == nil ? "New Maintenance Rule" : "Edit Maintenance Rule")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PalButtonStyle())
                Button("Save") {
                    let newRule = MaintenanceRule(
                        id: rule?.id ?? UUID().uuidString,
                        name: name.isEmpty ? "Untitled Rule" : name,
                        isEnabled: isEnabled,
                        sourceFolderURL: sourceFolderURL,
                        targetAction: targetAction,
                        destinationFolderURL: destinationFolderURL,
                        schedule: schedule,
                        minAgeDays: minAgeDays,
                        minFileBytes: minFileBytes,
                        notifyOnExecution: notifyOnExecution,
                        lastRunDate: rule?.lastRunDate
                    )
                    onSave(newRule)
                    dismiss()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
            .padding(20)
            Divider()

            Form {
                Section("Rule Details") {
                    TextField("Rule Name", text: $name)
                    Toggle("Rule Enabled", isOn: $isEnabled)
                }

                Section("Source Directory") {
                    HStack {
                        Text(sourceFolderURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose Folder…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                sourceFolderURL = url
                            }
                        }
                    }
                }

                Section("Action & Schedule") {
                    Picker("Action", selection: $targetAction) {
                        ForEach(MaintenanceAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }

                    if targetAction == .archiveToFolder {
                        HStack {
                            Text(destinationFolderURL?.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") ?? "No folder selected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Choose Destination…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    destinationFolderURL = url
                                }
                            }
                        }
                    }

                    Picker("Schedule", selection: $schedule) {
                        ForEach(MaintenanceSchedule.allCases) { sched in
                            Text(sched.title).tag(sched)
                        }
                    }
                }

                Section("Filters") {
                    Stepper("Items older than \(minAgeDays) days", value: $minAgeDays, in: 0...365, step: 5)
                    Picker("Minimum File Size", selection: $minFileBytes) {
                        Text("Any size").tag(Int64(0))
                        Text(">= 50 MB").tag(Int64(50_000_000))
                        Text(">= 100 MB").tag(Int64(100_000_000))
                        Text(">= 500 MB").tag(Int64(500_000_000))
                        Text(">= 1 GB").tag(Int64(1_000_000_000))
                    }
                }

                Section("Notifications") {
                    Toggle("Notify me on execution", isOn: $notifyOnExecution)
                }
            }
            .formStyle(.grouped)
            .padding(12)
        }
        .frame(minWidth: 540, minHeight: 520)
        .background(Color.palCream)
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
