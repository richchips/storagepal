import AppKit
import Foundation
import ServiceManagement

@MainActor
final class StartupManagerService: ObservableObject {
    static let shared = StartupManagerService()

    @Published private(set) var startupItems: [StartupItem] = []
    @Published private(set) var isLoading = false

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    func scanStartupItems() async -> [StartupItem] {
        isLoading = true
        defer { isLoading = false }

        var items: [StartupItem] = []

        // 1. Scan User LaunchAgents (~/Library/LaunchAgents)
        let userAgentsURL = home.appendingPathComponent("Library/LaunchAgents")
        items.append(contentsOf: scanLaunchDirectory(at: userAgentsURL, kind: .userLaunchAgent))

        // 2. Scan System LaunchAgents (/Library/LaunchAgents)
        let systemAgentsURL = URL(fileURLWithPath: "/Library/LaunchAgents")
        items.append(contentsOf: scanLaunchDirectory(at: systemAgentsURL, kind: .systemLaunchAgent))

        self.startupItems = items
        return items
    }

    /// Toggles the disabled state of a launch agent plist.
    func toggleItem(_ item: StartupItem, enable: Bool) -> Bool {
        guard let plistURL = item.plistURL, fm.fileExists(atPath: plistURL.path) else { return false }

        guard let data = try? Data(contentsOf: plistURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            return false
        }

        plist["Disabled"] = !enable

        guard let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return false
        }

        do {
            try updatedData.write(to: plistURL, options: .atomic)
            if let index = startupItems.firstIndex(where: { $0.id == item.id }) {
                startupItems[index].isEnabled = enable
            }
            return true
        } catch {
            AppErrorLogService.shared.log(
                category: "StartupManager",
                message: "Failed to toggle startup item \(item.name)",
                details: error.localizedDescription
            )
            return false
        }
    }

    /// Trashes the launch agent .plist file.
    func trashItem(_ item: StartupItem) -> TrashOperationResult {
        guard let plistURL = item.plistURL else {
            return .failure(reason: .fileNotFound(path: item.name))
        }

        let result = FileTrashService.shared.trashItem(at: plistURL, allowAdminElevation: true)
        if result.isSuccess {
            startupItems.removeAll { $0.id == item.id }
        }
        return result
    }

    // MARK: - Private Helpers

    private func scanLaunchDirectory(at directoryURL: URL, kind: StartupItemKind) -> [StartupItem] {
        guard fm.fileExists(atPath: directoryURL.path),
              let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        var results: [StartupItem] = []

        for fileURL in files where fileURL.pathExtension.lowercased() == "plist" {
            guard let data = try? Data(contentsOf: fileURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                continue
            }

            let label = plist["Label"] as? String ?? fileURL.deletingPathExtension().lastPathComponent
            let disabled = plist["Disabled"] as? Bool ?? false
            let runAtLoad = plist["RunAtLoad"] as? Bool ?? true

            var targetPath: String? = plist["Program"] as? String
            if targetPath == nil, let args = plist["ProgramArguments"] as? [String], let first = args.first {
                targetPath = first
            }

            var isMissing = false
            if let targetPath, !targetPath.isEmpty {
                // If path points to an executable, check if it exists
                if !fm.fileExists(atPath: targetPath) {
                    isMissing = true
                }
            }

            let itemKind: StartupItemKind = isMissing ? .orphanedAgent : kind
            let name = formatAgentName(label: label)

            results.append(
                StartupItem(
                    id: fileURL.path,
                    name: name,
                    label: label,
                    kind: itemKind,
                    plistURL: fileURL,
                    targetExecutablePath: targetPath,
                    isExecutableMissing: isMissing,
                    isEnabled: !disabled,
                    runAtLoad: runAtLoad
                )
            )
        }

        return results.sorted { (a, b) -> Bool in
            if a.isExecutableMissing && !b.isExecutableMissing { return true }
            if !a.isExecutableMissing && b.isExecutableMissing { return false }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    private func formatAgentName(label: String) -> String {
        let parts = label.split(separator: ".")
        if let last = parts.last, last.count > 2 {
            return String(last).capitalized
        }
        return label
    }
}
