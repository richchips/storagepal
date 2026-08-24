import SwiftUI

struct BrowserCleanerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBrowserIDs: Set<String> = []
    @State private var isCleaning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 580, minHeight: 480)
        .background(Color.palCream)
        .onAppear {
            selectedBrowserIDs = Set(model.browserCacheGroups.map { $0.id })
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.palMint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "globe")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.palMint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Browser Cache Cleaner")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Reclaim disk space by safely clearing disposable web caches and media buffers.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.palMuted)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(PalButtonStyle())
        }
        .padding(20)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Safety Guarantee Notice
                PalCard(padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.palMint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zero-Risk Session & Cookie Guarantee")
                                .font(.system(size: 12, weight: .bold))
                            Text("Storage Pal strictly clears only HTTP disk caches and media buffers. Your saved logins, cookies, passwords, and bookmarks are never touched.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }

                Text("DETECTED BROWSER CACHES (\(model.browserCacheGroups.count))")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.palMint)
                    .padding(.top, 4)

                VStack(spacing: 10) {
                    ForEach(model.browserCacheGroups) { group in
                        let isSelected = selectedBrowserIDs.contains(group.id)
                        PalCard(padding: 14) {
                            HStack(spacing: 14) {
                                Button {
                                    if isSelected {
                                        selectedBrowserIDs.remove(group.id)
                                    } else {
                                        selectedBrowserIDs.insert(group.id)
                                    }
                                } label: {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(isSelected ? Color.palMint : Color.palMuted)
                                }
                                .buttonStyle(.plain)

                                Image(systemName: group.browser.symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.palMint)
                                    .frame(width: 36, height: 36)
                                    .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(group.browser.rawValue)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(ByteText.string(group.bytes))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.palMint)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.palMint.opacity(0.11), in: Capsule())
                                    }
                                    Text(group.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.palMuted)
                                    Text("\(group.fileCount) cached files in \(group.cacheURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button("Show") {
                                    model.open(group.cacheURL)
                                }
                                .buttonStyle(PalButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            let totalSelectedBytes = model.browserCacheGroups
                .filter { selectedBrowserIDs.contains($0.id) }
                .reduce(0) { $0 + $1.bytes }

            Button(selectedBrowserIDs.count == model.browserCacheGroups.count ? "Deselect All" : "Select All") {
                if selectedBrowserIDs.count == model.browserCacheGroups.count {
                    selectedBrowserIDs.removeAll()
                } else {
                    selectedBrowserIDs = Set(model.browserCacheGroups.map { $0.id })
                }
            }
            .buttonStyle(PalButtonStyle())

            Spacer()

            Button("Clean Selected Caches (\(ByteText.string(totalSelectedBytes)))") {
                let targets = model.browserCacheGroups.filter { selectedBrowserIDs.contains($0.id) }
                isCleaning = true
                Task {
                    for target in targets {
                        await model.cleanBrowserCache(target)
                    }
                    isCleaning = false
                    dismiss()
                }
            }
            .buttonStyle(PalButtonStyle(prominent: true))
            .disabled(selectedBrowserIDs.isEmpty || isCleaning)
        }
        .padding(16)
    }
}
