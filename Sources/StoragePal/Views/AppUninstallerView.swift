import SwiftUI

enum UninstallerTab: String, CaseIterable, Identifiable {
    case installed = "Installed Apps"
    case orphaned = "Orphaned Leftovers"
    var id: String { rawValue }
}

@MainActor
struct AppUninstallerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: UninstallerTab = .installed
    @State private var searchText = ""
    @State private var confirmingApp: InstalledApp?
    @State private var selectedResidueIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Apps",
                        title: selectedTab == .installed ? "Smart App Uninstaller" : "Orphaned App Residue",
                        detail: selectedTab == .installed
                            ? "Remove applications cleanly along with their hidden Library support folders, containers, and caches."
                            : "Clean support folders left behind in ~/Library by applications that were uninstalled in the past."
                    )
                    Spacer()
                    Button {
                        if selectedTab == .installed {
                            model.scanInstalledApps()
                        } else {
                            model.scanOrphanedResidues()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PalButtonStyle())
                }

                if !model.hasFullDiskAccess {
                    fdaAdvisoryBanner
                }

                Picker("View Mode", selection: $selectedTab) {
                    Text("Installed Apps (\(model.installedApps.count))").tag(UninstallerTab.installed)
                    Text("Orphaned Leftovers (\(model.orphanedResidues.count))").tag(UninstallerTab.orphaned)
                }
                .pickerStyle(.segmented)

                searchBar

                if selectedTab == .installed {
                    if model.installedApps.isEmpty {
                        PalCard {
                            HStack(spacing: 20) {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color.palMint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scan Installed Applications")
                                        .font(.system(size: 15, weight: .bold))
                                    Text("Storage Pal will discover installed apps in /Applications and calculate their associated Library caches and support directories.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.palMuted)
                                }
                                Spacer()
                                Button("Scan Apps Now") {
                                    model.scanInstalledApps()
                                }
                                .buttonStyle(PalButtonStyle(prominent: true))
                            }
                        }
                    } else {
                        appList
                    }
                } else {
                    orphanedResiduesView
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onAppear {
            if model.installedApps.isEmpty {
                model.scanInstalledApps()
            }
            if model.orphanedResidues.isEmpty {
                model.scanOrphanedResidues()
            }
        }
        .sheet(item: $confirmingApp) { app in
            AppUninstallDetailSheet(app: app)
                .environmentObject(model)
        }
        .sheet(item: $model.permissionRecoveryContext) { context in
            PermissionRecoverySheet(context: context)
                .environmentObject(model)
        }
    }

    private var fdaAdvisoryBanner: some View {
        PalCard(padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Full Disk Access Recommended")
                        .font(.system(size: 13, weight: .bold))
                    Text("To cleanly remove sandboxed application containers in ~/Library/Containers, macOS requires Full Disk Access.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }

                Spacer()

                Button("Grant Access in Settings") {
                    model.openFullDiskAccessSettings()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search installed applications…", text: $searchText)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var filteredApps: [InstalledApp] {
        if searchText.isEmpty { return model.installedApps }
        return model.installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            (app.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var appList: some View {
        VStack(spacing: 12) {
            ForEach(filteredApps) { app in
                PalCard(padding: 18) {
                    HStack(spacing: 16) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.palMint)
                            .frame(width: 44, height: 44)
                            .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(app.name)
                                    .font(.system(size: 14, weight: .bold))
                                Text(ByteText.string(app.totalReclaimableBytes))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.palMint)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.palMint.opacity(0.11), in: Capsule())
                            }

                            HStack(spacing: 10) {
                                Text(app.bundleIdentifier ?? app.appURL.path)
                                if !app.leftovers.isEmpty {
                                    Text("•")
                                    Text("\(app.leftovers.count) Library leftover(s) (\(ByteText.string(app.leftoverSizeBytes)))")
                                        .foregroundStyle(Color.palMint)
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                            .lineLimit(1)
                        }

                        Spacer()

                        Button("Uninstall…") {
                            confirmingApp = app
                        }
                        .buttonStyle(PalButtonStyle(prominent: true))
                    }
                }
            }
        }
    }

    private var filteredResidues: [OrphanedAppResidue] {
        if searchText.isEmpty { return model.orphanedResidues }
        return model.orphanedResidues.filter { res in
            res.name.localizedCaseInsensitiveContains(searchText) ||
            res.category.localizedCaseInsensitiveContains(searchText) ||
            (res.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            res.url.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var orphanedResiduesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            let totalResidueBytes = model.orphanedResidues.reduce(0) { $0 + $1.bytes }
            let selectedBytes = model.orphanedResidues
                .filter { selectedResidueIDs.contains($0.id) }
                .reduce(0) { $0 + $1.bytes }

            // Summary Action Bar with Single-Prompt Batch Authorization
            PalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.orphanedResidues.count) Orphaned Support Folders (\(ByteText.string(totalResidueBytes)))")
                                .font(.system(size: 13, weight: .bold))
                            Text("Leftover containers and preferences from apps no longer installed on your Mac.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }

                        Spacer()

                        Button(selectedResidueIDs.count == model.orphanedResidues.count ? "Deselect All" : "Select All") {
                            if selectedResidueIDs.count == model.orphanedResidues.count {
                                selectedResidueIDs.removeAll()
                            } else {
                                selectedResidueIDs = Set(model.orphanedResidues.map { $0.id })
                            }
                        }
                        .buttonStyle(PalButtonStyle())

                        if !selectedResidueIDs.isEmpty {
                            Button {
                                let toTrash = model.orphanedResidues.filter { selectedResidueIDs.contains($0.id) }
                                selectedResidueIDs.removeAll()
                                model.trashOrphanedResidues(toTrash)
                            } label: {
                                Label("Allow All & Trash (\(selectedResidueIDs.count) • \(ByteText.string(selectedBytes)))", systemImage: "checkmark.shield.fill")
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        } else {
                            Button {
                                model.trashOrphanedResidues(model.orphanedResidues)
                            } label: {
                                Label("Allow All & Clean Leftovers", systemImage: "checkmark.shield.fill")
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                            .disabled(model.orphanedResidues.isEmpty)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMint)
                        Text("Fast Single Authorization: Storage Pal groups all items into a single atomic action so you only confirm once.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }
                }
            }

            if model.orphanedResidues.isEmpty {
                PalCard {
                    HStack(spacing: 20) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Orphaned App Leftovers")
                                .font(.system(size: 15, weight: .bold))
                            Text("All Application Support folders, containers, and caches in ~/Library match currently installed applications.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredResidues) { res in
                        let isSelected = selectedResidueIDs.contains(res.id)
                        PalCard(padding: 14) {
                            HStack(spacing: 14) {
                                Button {
                                    if isSelected {
                                        selectedResidueIDs.remove(res.id)
                                    } else {
                                        selectedResidueIDs.insert(res.id)
                                    }
                                } label: {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(isSelected ? Color.palMint : Color.palMuted)
                                }
                                .buttonStyle(.plain)

                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.orange)
                                    .frame(width: 38, height: 38)
                                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(res.name)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(ByteText.string(res.bytes))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.palMint)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.palMint.opacity(0.11), in: Capsule())
                                        Text(res.category)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.palMuted)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.palMuted.opacity(0.1), in: Capsule())
                                    }

                                    Text(res.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button("Show") {
                                    model.open(res.url)
                                }
                                .buttonStyle(PalButtonStyle())

                                Button("Trash") {
                                    model.trashOrphanedResidues([res])
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
    }
}

@MainActor
private struct AppUninstallDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Uninstall “\(app.name)”")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Reclaim \(ByteText.string(app.totalReclaimableBytes)) by moving the app and its support files to Trash.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PalButtonStyle())
            }
            .padding(20)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ITEMS TO BE MOVED TO TRASH")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.palMint)

                    HStack(spacing: 12) {
                        Image(systemName: "app.fill")
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Application Bundle")
                                .font(.system(size: 12, weight: .bold))
                            Text("\(app.appURL.path) (\(ByteText.string(app.appSizeBytes)))")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 10))

                    if !app.leftovers.isEmpty {
                        Text("LIBRARY LEFTOVERS (\(app.leftovers.count))")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.palMint)
                            .padding(.top, 8)

                        ForEach(app.leftovers) { leftover in
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(leftover.category)
                                        .font(.system(size: 12, weight: .bold))
                                    Text("\(leftover.url.path) (\(ByteText.string(leftover.bytes)))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.palMuted)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if !model.hasFullDiskAccess && app.leftovers.contains(where: { $0.category == "Containers" || $0.category == "Group Containers" }) {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Some leftovers are in sandbox containers. If macOS prompts for authorization, Storage Pal will guide you through granting permission.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMint)
                    Text("Single Authorization: App and all support items are trashed in 1 step.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()
                Button {
                    model.uninstallApp(app)
                    dismiss()
                } label: {
                    Label("Allow All & Move to Trash", systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
            .padding(16)
        }
        .frame(minWidth: 580, minHeight: 460)
        .background(Color.palCream)
    }
}
