import QuickLook
import SwiftUI

struct TreemapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var currentRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var navigationHistory: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @State private var rootNode: TreemapNode?
    @State private var selectedNode: TreemapNode?
    @State private var isLoading = false
    @State private var previewURL: URL?

    private let colors: [Color] = [
        Color.palMint,
        Color.blue.opacity(0.85),
        Color.purple.opacity(0.85),
        Color.orange.opacity(0.85),
        Color.teal.opacity(0.85),
        Color.indigo.opacity(0.85),
        Color.pink.opacity(0.85)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView().tint(Color.palMint)
                    Text("Mapping storage layout…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.palMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let rootNode, !rootNode.children.isEmpty {
                HStack(spacing: 0) {
                    GeometryReader { geo in
                        let laidOutChildren = TreemapBuilder.layout(nodes: rootNode.children, in: CGRect(origin: .zero, size: geo.size))
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(laidOutChildren.enumerated()), id: \.element.id) { index, node in
                                treemapCell(node: node, color: colors[index % colors.count])
                            }
                        }
                    }
                    .padding(20)

                    if let selected = selectedNode {
                        Divider()
                        inspectorBar(for: selected)
                            .frame(width: 260)
                            .background(Color.palSidebarBackground)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "square.split.2x2")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.palMint)
                    Text("No large items found in this directory.")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.palCream)
        .quickLookPreview($previewURL)
        .onAppear {
            loadTree(for: currentRootURL)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                if navigationHistory.count > 1 {
                    navigationHistory.removeLast()
                    if let previous = navigationHistory.last {
                        currentRootURL = previous
                        loadTree(for: previous)
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(PalButtonStyle())
            .disabled(navigationHistory.count <= 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(currentRootURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                if let rootNode {
                    Text("\(ByteText.string(rootNode.bytes)) total in \(rootNode.children.count) items")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
            }

            Spacer()

            Menu("Jump to…") {
                Button("Home (~)") { navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
                Button("Downloads") { navigate(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) }
                Button("Documents") { navigate(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")) }
                Button("Desktop") { navigate(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")) }
                Button("Movies") { navigate(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")) }
                Button("Library Caches") { navigate(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")) }
                Button("Xcode Developer") { navigate(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer")) }
            }
            .buttonStyle(PalButtonStyle())

            Button {
                loadTree(for: currentRootURL)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PalButtonStyle())
        }
        .padding(16)
    }

    private func treemapCell(node: TreemapNode, color: Color) -> some View {
        let isSelected = selectedNode?.id == node.id
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(isSelected ? 0.95 : 0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.white : Color.black.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
                )

            if node.rect.width > 60 && node.rect.height > 40 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(ByteText.string(node.bytes))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(6)
            }
        }
        .frame(width: max(node.rect.width - 4, 1), height: max(node.rect.height - 4, 1))
        .position(x: node.rect.origin.x + node.rect.width / 2, y: node.rect.origin.y + node.rect.height / 2)
        .onTapGesture {
            selectedNode = node
        }
        .onTapGesture(count: 2) {
            if node.isDirectory {
                navigate(to: node.url)
            }
        }
    }

    private func inspectorBar(for node: TreemapNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.palMint)
                Text(node.name)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(2)
            }

            Text(ByteText.string(node.bytes))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.palInk)

            Text(node.url.path)
                .font(.system(size: 10))
                .foregroundStyle(Color.palMuted)
                .lineLimit(4)

            Divider()

            if node.isDirectory {
                Button("Zoom into Folder") {
                    navigate(to: node.url)
                }
                .buttonStyle(PalButtonStyle(prominent: true))
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    previewURL = node.url
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .buttonStyle(PalButtonStyle())
                .frame(maxWidth: .infinity)
            }

            Button("Show in Finder") {
                model.open(node.url)
            }
            .buttonStyle(PalButtonStyle())
            .frame(maxWidth: .infinity)

            Button("Move to Trash") {
                let result = model.trashService.trashItem(at: node.url, allowAdminElevation: true)
                if result.isSuccess {
                    selectedNode = nil
                    loadTree(for: currentRootURL)
                } else if case .failure(let reason) = result {
                    if reason.isPermissionOrTCC {
                        model.permissionRecoveryContext = PermissionRecoveryContext(
                            title: "Permissions Needed to Trash Item",
                            subtitle: reason.userFacingDescription,
                            appName: nil,
                            app: nil,
                            blockedItems: [
                                BatchTrashItemReport(
                                    url: node.url,
                                    name: node.name,
                                    bytes: node.bytes,
                                    category: node.isDirectory ? "Folder" : "File",
                                    result: result
                                )
                            ],
                            onRetry: {
                                let retryResult = model.trashService.trashItem(at: node.url, allowAdminElevation: true)
                                if retryResult.isSuccess {
                                    selectedNode = nil
                                    loadTree(for: currentRootURL)
                                }
                            }
                        )
                    } else if reason != .userCanceled {
                        model.errorMessage = "Could not trash item: \(reason.userFacingDescription)"
                    }
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .padding(.top, 8)

            Spacer()
        }
        .padding(18)
    }

    private func navigate(to url: URL) {
        navigationHistory.append(url)
        currentRootURL = url
        selectedNode = nil
        loadTree(for: url)
    }

    private func loadTree(for url: URL) {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let tree = TreemapBuilder.buildTree(for: url, maxDepth: 1)
            await MainActor.run {
                self.rootNode = tree
                self.isLoading = false
            }
        }
    }
}
