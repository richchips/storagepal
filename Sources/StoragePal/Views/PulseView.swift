import SwiftUI

private extension PulseState {
    var tint: Color {
        switch self {
        case .clear: .palMint
        case .review: Color(red: 0.70, green: 0.43, blue: 0.15)
        case .manual, .unavailable: .palMuted
        }
    }
}

struct PulseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = "All checks"
    private let filters = ["All checks", "Worth a look", "Not verified"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(eyebrow: "Your device, in rhythm", title: "Pulse",
                                   detail: "A clear check-in. A little more breathing room.")
                    Spacer()
                    Button {
                        model.isPulseScanning ? model.cancelPulse() : model.runPulse()
                    } label: {
                        Label(model.isPulseScanning ? "Cancel check" : model.pulseReport == nil ? "Run Pulse" : "Check again",
                              systemImage: model.isPulseScanning ? "stop.circle" : "waveform.path.ecg")
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                    .disabled(model.isActivityScanning && !model.isPulseScanning)
                }

                if model.isPulseScanning {
                    PalCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(model.pulseMessage, systemImage: "waveform.path.ecg")
                                .font(.headline)
                            ProgressView(value: model.pulseProgress).tint(.palMint)
                                .accessibilityLabel("Pulse check progress")
                            Text("Reading local information only. You can cancel at any time.")
                                .font(.callout).foregroundStyle(Color.palMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let report = model.pulseReport {
                    summary(report)
                    HStack {
                        Text("YOUR CHECKS").font(.caption.bold()).tracking(1.2)
                        Spacer()
                        Picker("Show checks", selection: $filter) {
                            ForEach(filters, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.segmented).frame(maxWidth: 360)
                    }
                    let checks = report.checks.filter {
                        filter == "All checks" || (filter == "Worth a look" ? $0.state == .review : $0.state == .manual || $0.state == .unavailable)
                    }
                    if checks.isEmpty {
                        Text("No checks in this group.").foregroundStyle(Color.palMuted)
                    }
                    ForEach(checks) { check in checkRow(check) }
                    Text("Snapshot from \(report.createdAt.formatted(date: .abbreviated, time: .shortened)). Run Pulse again after making changes. This is a maintenance check-in, not a hardware diagnostic, malware scan, or security certification.")
                        .font(.caption).foregroundStyle(Color.palMuted)
                } else {
                    introduction
                    if model.pulseMessage != "Ready when you are" {
                        Text(model.pulseMessage).font(.callout).foregroundStyle(Color.palMuted)
                    }
                }

                toolLinks
                Label("Review first. Files go to Trash only after you confirm. Pulse never empties Trash.", systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(Color.palMuted)
            }
            .padding(34)
            .frame(maxWidth: 1060, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.palInk)
    }

    private var introduction: some View {
        PalCard(padding: 28) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(Color.palMint)
                        .frame(width: 90, height: 90)
                        .background(Color.palMint.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find your device’s happy place.")
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                        Text("See what is taking up space, what is running, and which settings deserve a look — in one calm overview.")
                            .foregroundStyle(Color.palMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 24) {
                    pillar("Make room", detail: "Storage & local caches", symbol: "externaldrive")
                    pillar("Find your flow", detail: "Startup & app activity", symbol: "waveform.path")
                    pillar("Stay in control", detail: "Privacy & update checklist", symbol: "lock.shield")
                }
                Text("Every check shows its evidence, scope, and anything Pulse could not verify.")
                    .font(.callout).foregroundStyle(Color.palMuted)
            }
        }
    }

    private func pillar(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.palMint)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(Color.palMuted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ report: PulseReport) -> some View {
        PalCard(padding: 26) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.headline).font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("\(report.reviewCount) areas worth a look · \(report.unverifiedCount) needing a manual or unavailable check")
                            .font(.callout).foregroundStyle(Color.palMuted)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(report.verifiedCount)/\(report.checks.count)")
                            .font(.system(size: 35, weight: .light, design: .rounded)).monospacedDigit()
                        Text("checks verified").font(.caption).foregroundStyle(Color.palMuted)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(report.checks) { check in
                        Capsule().fill(check.state.tint.opacity(check.state == .unavailable || check.state == .manual ? 0.25 : 0.8))
                            .frame(height: 7)
                            .help("\(check.area.title): \(check.state.rawValue)")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(report.verifiedCount) of \(report.checks.count) checks verified; \(report.reviewCount) worth reviewing")
                Text(model.pulseMessage).font(.caption).foregroundStyle(Color.palMuted)
            }
        }
    }

    private func checkRow(_ check: PulseCheck) -> some View {
        PalCard(padding: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: check.area.symbol).font(.system(size: 22))
                    .foregroundStyle(Color.palMint).frame(width: 40, height: 42)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(check.area.title).font(.headline)
                        Spacer()
                        Label(check.state.rawValue, systemImage: check.state.symbol)
                            .font(.caption.weight(.medium)).foregroundStyle(check.state.tint)
                    }
                    Text(check.detail).font(.callout).foregroundStyle(Color.palMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(check.metric).font(.callout.weight(.semibold))
                        Spacer()
                        if check.area != .cleanup || !model.pulseCacheCandidates.isEmpty {
                            Button(check.area.actionLabel) { model.reviewPulse(check.area) }
                                .buttonStyle(PalButtonStyle())
                        } else if check.state == .unavailable {
                            Button("Review permissions") { model.openFilesAndFoldersSettings() }
                                .buttonStyle(PalButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var toolLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GO A LITTLE DEEPER").font(.caption.bold()).tracking(1.2).foregroundStyle(Color.palMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                tool("Custom cleanup", symbol: "checklist", section: .tidy)
                tool("Uninstall apps", symbol: "app.badge.checkmark", section: .apps)
                tool("Find duplicates", symbol: "doc.on.doc", section: .duplicates)
                tool("Cloud storage", symbol: "icloud", section: .iCloud)
            }
        }
    }

    private func tool(_ title: String, symbol: String, section: DashboardSection) -> some View {
        Button { model.dashboardSection = section } label: {
            Label(title, systemImage: symbol).font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}

struct PulseActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingQuit: PulseAppActivity?
    @State private var onlyReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(eyebrow: "Find your flow", title: "Activity",
                               detail: "See which apps are busy before deciding what to close.")
                HStack {
                    Button("Refresh snapshot") { Task { await model.refreshPulseActivity() } }
                        .buttonStyle(PalButtonStyle(prominent: true))
                        .disabled(model.isActivityScanning || model.isPulseScanning)
                    Button("Activity Monitor") { model.openActivityMonitor() }.buttonStyle(PalButtonStyle())
                    Spacer()
                    if model.isActivityScanning { ProgressView().controlSize(.small) }
                }
                PalCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Busy doesn’t mean unnecessary.").font(.headline)
                        Text("Pulse highlights app processes at 20% CPU or 1 GB resident memory. This is a single reading, not sustained load or total app memory. CPU can exceed 100% across cores. System processes and app helpers are excluded; use Activity Monitor for the full picture.")
                            .font(.callout).foregroundStyle(Color.palMuted)
                        if let date = model.activityCheckedAt {
                            Text("Sampled \(date.formatted(date: .omitted, time: .standard)). Refresh after closing an app.")
                                .font(.caption).foregroundStyle(Color.palMuted)
                        }
                    }
                }
                if let error = model.activityError {
                    Label(error, systemImage: "questionmark.circle").foregroundStyle(Color.palMuted)
                }
                Toggle("Show only apps worth a look", isOn: $onlyReview).toggleStyle(.switch)
                let apps = model.pulseActivity.filter { !onlyReview || $0.warrantsReview }
                if apps.isEmpty && !model.isActivityScanning {
                    Text(model.activityCheckedAt == nil ? "Refresh to take a local activity snapshot." : "No app processes match this view.")
                        .foregroundStyle(Color.palMuted)
                }
                ForEach(apps) { activity in
                    PalCard(padding: 16) {
                        HStack(spacing: 16) {
                            Image(systemName: activity.app.isBackground ? "menubar.rectangle" : "app")
                                .font(.title2).foregroundStyle(Color.palMint)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(activity.app.name).font(.headline)
                                Text(activity.app.isBackground ? "Menu bar / background app" : "Open app")
                                    .font(.caption).foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text("\(activity.cpuPercent, specifier: "%.1f")% CPU").monospacedDigit()
                                Text("\(ByteText.string(activity.residentBytes)) resident")
                                    .font(.caption).foregroundStyle(Color.palMuted)
                            }
                            Button("Request quit…") { pendingQuit = activity }
                                .buttonStyle(PalButtonStyle()).disabled(activity.app.launchDate == nil)
                        }
                    }
                }
            }.padding(34).frame(maxWidth: 1060, alignment: .leading).frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.palInk)
        .alert("Ask this app to quit?", isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } }), presenting: pendingQuit) { activity in
            Button("Cancel", role: .cancel) { pendingQuit = nil }
            Button("Request quit") { model.requestQuit(activity); pendingQuit = nil }
        } message: { activity in
            Text("Save your work in \(activity.app.name) first. This sends a normal quit request. The app may ask you to save or refuse to quit. Pulse never force-quits or suspends apps.")
        }
    }
}

struct PulseUpdatesView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = AppUpdateService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(eyebrow: "Stay in control", title: "Updates",
                               detail: "The right update source for each part of your device.")
                Label("System, app and driver updates require a manual check. Unknown versions are never counted as outdated.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(Color.palMuted)
                updateCard("System software", symbol: "desktopcomputer", detail: "Installed: \(ProcessInfo.processInfo.operatingSystemVersionString). Use System Settings to check compatible system and security updates.", action: "Open Software Update", perform: model.openSoftwareUpdateSettings)
                updateCard("App Store apps", symbol: "app.badge", detail: "The App Store checks updates for apps installed through your account. Pulse does not have access to that update inventory.", action: "Open App Store updates", perform: model.openAppStoreUpdates)
                updateCard("Apps from developers", symbol: "shippingbox", detail: "Open each app’s Check for Updates menu or its developer’s official updater. Installed apps are not marked outdated just because they have an older installation date.", action: "Browse installed apps") { model.dashboardSection = .apps }
                updateCard("Drivers & connected devices", symbol: "cable.connector", detail: "Start with system updates. For peripherals that need separate software or firmware, use the manufacturer’s official updater. Pulse does not scan or replace drivers.", action: "Open Software Update", perform: model.openSoftwareUpdateSettings)
                PalCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Storage Pal", systemImage: "archivebox").font(.headline)
                        Text("Installed version \(updater.currentVersion) · \(updateStatus)")
                            .font(.callout).foregroundStyle(Color.palMuted)
                        if let date = updater.lastCheckDate {
                            Text("Last check attempt: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(Color.palMuted)
                        }
                        Button("Check Storage Pal updates…") {
                            Task { await updater.checkForUpdates(userInitiated: true) }
                        }.buttonStyle(PalButtonStyle(prominent: true))
                            .disabled(updater.status.isCheckingOrDownloading)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(34).frame(maxWidth: 1060, alignment: .leading).frame(maxWidth: .infinity)
        }.foregroundStyle(Color.palInk)
    }

    private var updateStatus: String {
        switch updater.status {
        case .idle: "Not checked in this session"
        case .checking: "Checking…"
        case .upToDate: "Up to date at last check"
        case .updateAvailable(let release): "Version \(release.version) available"
        case .downloading: "Downloading…"
        case .readyToRelaunch: "Ready to relaunch"
        case .failed: "Last check could not be completed"
        }
    }

    private func updateCard(_ title: String, symbol: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        PalCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol).font(.headline)
                Text(detail).font(.callout).foregroundStyle(Color.palMuted)
                Button(action, action: perform).buttonStyle(PalButtonStyle())
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
