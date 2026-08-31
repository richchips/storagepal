import AppKit
import Foundation
import ServiceManagement

@MainActor
final class StartupManagerService: ObservableObject {
    static let shared = StartupManagerService()

    @Published private(set) var startupItems: [StartupItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var scanWarnings: [String] = []

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    func scanStartupItems() async -> [StartupItem] {
        isLoading = true
        defer { isLoading = false }

        let userAgentsURL = home.appendingPathComponent("Library/LaunchAgents")
        let worker = Task.detached(priority: .utility) {
            var warnings: [String] = []
            var items = Self.scanLaunchDirectory(at: userAgentsURL, kind: .userLaunchAgent, warnings: &warnings)
            items += Self.scanLaunchDirectory(at: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .systemLaunchAgent, warnings: &warnings)
            return (items, warnings)
        }
        let (items, warnings) = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        if !Task.isCancelled {
            self.startupItems = items
            self.scanWarnings = warnings
        }
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

    nonisolated private static func scanLaunchDirectory(at directoryURL: URL, kind: StartupItemKind, warnings: inout [String]) -> [StartupItem] {
        let fm = FileManager.default
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            if !PulseService.isMissingFile(error) { warnings.append(directoryURL.path) }
            return []
        }

        var results: [StartupItem] = []

        for fileURL in files where fileURL.pathExtension.lowercased() == "plist" {
            if Task.isCancelled { break }
            guard let data = try? Data(contentsOf: fileURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                warnings.append(fileURL.path)
                continue
            }

            let label = plist["Label"] as? String ?? fileURL.deletingPathExtension().lastPathComponent
            let disabled = plist["Disabled"] as? Bool ?? false
            let runAtLoad = plist["RunAtLoad"] as? Bool ?? false

            var targetPath: String? = plist["Program"] as? String
            if targetPath == nil, let args = plist["ProgramArguments"] as? [String], let first = args.first {
                targetPath = first
            }

            var isMissing = false
            if let targetPath, targetPath.hasPrefix("/") {
                // Relative commands are resolved by launchd; unreadable is not missing.
                do { _ = try fm.attributesOfItem(atPath: targetPath) }
                catch { isMissing = PulseService.isMissingFile(error) }
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

    nonisolated private static func formatAgentName(label: String) -> String {
        let parts = label.split(separator: ".")
        if let last = parts.last, last.count > 2 {
            return String(last).capitalized
        }
        return label
    }
}
