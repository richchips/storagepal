import SwiftUI

struct StartupManagerView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var startupService = StartupManagerService.shared
    @State private var searchText = ""
    @State private var selectedKind: StartupItemKind?

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
                                Text("Your Mac is clean. No third-party LaunchAgents or startup helpers were discovered in ~/Library/LaunchAgents.")
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
                    Text("ACTIVE AT BOOT")
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
                                set: { _ = startupService.toggleItem(item, enable: $0) }
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
                            _ = startupService.trashItem(item)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
