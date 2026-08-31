import SwiftUI

struct StartupManagerView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var startupService = StartupManagerService.shared
    @State private var searchText = ""
    @State private var selectedKind: StartupItemKind?
    @State private var pendingTrash: StartupItem?
    @State private var pendingToggle: StartupItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Startup",
                        title: "Startup & Background Items",
                        detail: "Manage background LaunchAgents and startup daemons. Clean broken background items left by uninstalled apps."
                    )
                    Spacer()
                    Button {
                        Task { await startupService.scanStartupItems() }
                    } label: {
                        Label(startupService.startupItems.isEmpty ? "Scan Items" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PalButtonStyle())
                }

                summaryRow

                PalCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("These are LaunchAgent configurations, not a list of unnecessary apps. Configuration changes may take effect at next login; running helpers are not stopped.")
                            .font(.callout).foregroundStyle(Color.palMuted)
                        if !startupService.scanWarnings.isEmpty {
                            Text("Some startup locations could not be read. These results are incomplete.")
                                .font(.callout).foregroundStyle(Color.palMuted)
                        }
                        Button("Open Login Items & Extensions") { model.openLoginItemsSettings() }
                            .buttonStyle(PalButtonStyle())
                    }
                }

                searchAndFilterBar

                if startupService.isLoading {
                    PalCard {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning startup items and background agents…")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                } else if startupService.startupItems.isEmpty {
                    PalCard {
                        HStack(spacing: 20) {
                            Image(systemName: "gearshape.2")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.palMint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No Background LaunchAgents Found")
                                    .font(.system(size: 15, weight: .bold))
                                Text("No LaunchAgents were found in the accessible user and shared Library folders. Check Login Items in Settings for other startup apps.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Spacer()
                            Button("Re-Scan") {
                                Task { await startupService.scanStartupItems() }
                            }
                            .buttonStyle(PalButtonStyle(prominent: true))
                        }
                    }
                } else {
                    itemList
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onAppear {
            if startupService.startupItems.isEmpty {
                Task { await startupService.scanStartupItems() }
            }
        }
        .alert("Move startup helper to Trash?", isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }), presenting: pendingTrash) { item in
            Button("Cancel", role: .cancel) { pendingTrash = nil }
            Button("Move to Trash", role: .destructive) {
                let result = startupService.trashItem(item)
                if !result.isSuccess { model.errorMessage = "The startup helper could not be moved to Trash. Check permissions and try again." }
                pendingTrash = nil
            }
        } message: { item in
            Text("This removes the launch configuration for \(item.name). It may affect the app’s background features at next login. The file stays recoverable in Trash; any running helper is not stopped.")
        }
        .alert("Change startup configuration?", isPresented: Binding(get: { pendingToggle != nil }, set: { if !$0 { pendingToggle = nil } }), presenting: pendingToggle) { item in
            Button("Cancel", role: .cancel) { pendingToggle = nil }
            Button(item.isEnabled ? "Disable configuration" : "Enable configuration") {
                if !startupService.toggleItem(item, enable: !item.isEnabled) {
                    model.errorMessage = "The startup configuration could not be changed. Use Login Items in System Settings or the app’s preferences."
                }
                pendingToggle = nil
            }
        } message: { item in
            Text("This changes the launch configuration for \(item.name). It does not stop a running helper, and system overrides may take precedence. Use Login Items in Settings to manage current login behavior.")
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            let orphanedCount = startupService.startupItems.filter { $0.isExecutableMissing }.count
            let activeCount = startupService.startupItems.filter { $0.isEnabled }.count

            PalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOTAL BACKGROUND ITEMS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.palMint)
                    Text("\(startupService.startupItems.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONFIGURED ENABLED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.palInk)
                    Text("\(activeCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ORPHANED / BROKEN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(orphanedCount > 0 ? .orange : Color.palMuted)
                    Text("\(orphanedCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(orphanedCount > 0 ? .orange : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var searchAndFilterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search startup helpers & LaunchAgents…", text: $searchText)
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

    private var filteredItems: [StartupItem] {
        var items = startupService.startupItems
        if !searchText.isEmpty {
            items = items.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.label.localizedCaseInsensitiveContains(searchText) ||
                (item.targetExecutablePath?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return items
    }

    private var itemList: some View {
        VStack(spacing: 12) {
            ForEach(filteredItems) { item in
                PalCard(padding: 16) {
                    HStack(spacing: 16) {
                        Image(systemName: item.kind.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(item.isExecutableMissing ? .orange : Color.palMint)
                            .frame(width: 42, height: 42)
                            .background(
                                (item.isExecutableMissing ? Color.orange : Color.palMint).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 11)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .bold))

                                if item.isExecutableMissing {
                                    Text("Broken (Executable Missing)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                } else {
                                    Text(item.kind.rawValue)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.palMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.palMuted.opacity(0.1), in: Capsule())
                                }
                            }

                            Text(item.label)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                                .lineLimit(1)

                            if let targetPath = item.targetExecutablePath {
                                Text(targetPath.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(item.isExecutableMissing ? .orange.opacity(0.8) : .secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if !item.isExecutableMissing {
                            Toggle("", isOn: Binding(
                                get: { item.isEnabled },
                                set: { _ in pendingToggle = item }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        if let plistURL = item.plistURL {
                            Button("Show") {
                                model.open(plistURL)
                            }
                            .buttonStyle(PalButtonStyle())
                        }

                        Button("Trash") {
                            pendingTrash = item
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
