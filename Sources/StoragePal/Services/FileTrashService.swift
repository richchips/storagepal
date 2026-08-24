import AppKit
import Foundation

enum TrashMethod: String, Sendable {
    case foundation = "Standard Trash"
    case unlockedAndTrashed = "Unlocked & Trashed"
    case finderAppleScript = "Finder System Trash"
    case privilegedAdminMove = "Admin Authorized Move (Single Prompt)"
}

enum TrashFailureReason: Equatable, Sendable {
    case fullDiskAccessRequired(path: String)
    case permissionDenied(path: String, message: String)
    case fileNotFound(path: String)
    case userCanceled
    case unknown(message: String)

    var userFacingDescription: String {
        switch self {
        case .fullDiskAccessRequired(let path):
            return "macOS restricted access to “\(path)”. Grant Full Disk Access in System Settings to remove this item."
        case .permissionDenied(let path, let message):
            return "Permission was denied for “\(path)”: \(message)"
        case .fileNotFound(let path):
            return "Item was not found at “\(path)”."
        case .userCanceled:
            return "Authorization was canceled by the user."
        case .unknown(let message):
            return message
        }
    }

    var isPermissionOrTCC: Bool {
        switch self {
        case .fullDiskAccessRequired, .permissionDenied:
            return true
        case .userCanceled, .fileNotFound, .unknown:
            return false
        }
    }
}

enum TrashOperationResult: Sendable {
    case success(method: TrashMethod)
    case failure(reason: TrashFailureReason)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isPermissionFailure: Bool {
        if case .failure(let reason) = self {
            return reason.isPermissionOrTCC
        }
        return false
    }
}

struct BatchTrashItemReport: Identifiable, Sendable {
    let id: String
    let url: URL
    let name: String
    let bytes: Int64
    let category: String
    let result: TrashOperationResult

    init(url: URL, name: String, bytes: Int64, category: String, result: TrashOperationResult) {
        self.id = url.path
        self.url = url
        self.name = name
        self.bytes = bytes
        self.category = category
        self.result = result
    }
}

struct BatchTrashSummary: Sendable {
    let items: [BatchTrashItemReport]
    let totalAttempted: Int
    let successCount: Int
    let reclaimedBytes: Int64

    var failedItems: [BatchTrashItemReport] {
        items.filter { !$0.result.isSuccess }
    }

    var successfulItems: [BatchTrashItemReport] {
        items.filter { $0.result.isSuccess }
    }

    var hasFailures: Bool {
        !failedItems.isEmpty
    }

    var hasPermissionFailures: Bool {
        failedItems.contains { $0.result.isPermissionFailure }
    }
}

@MainActor
final class FileTrashService {
    static let shared = FileTrashService()

    private let fm = FileManager.default

    init() {}

    /// Safely moves a single file or directory to Trash using multi-tier progressive fallbacks.
    func trashItem(at url: URL, allowAdminElevation: Bool = true) -> TrashOperationResult {
        guard fm.fileExists(atPath: url.path) else {
            return .failure(reason: .fileNotFound(path: url.path))
        }

        // Tier 1: Standard Foundation trashItem
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            return .success(method: .foundation)
        } catch let error as NSError {
            AppErrorLogService.shared.log(
                category: "TrashService",
                message: "Tier 1 Foundation trash failed for \(url.lastPathComponent)",
                details: error.localizedDescription
            )
        }

        // Tier 2: Unlock file / clear immutable flags & add user write permissions, then retry
        unlockAndMakeWritable(at: url)
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            return .success(method: .unlockedAndTrashed)
        } catch {
            // Proceed to Tier 3
        }

        // Tier 3: Ask macOS Finder via AppleScript
        let finderResult = trashWithFinder(url: url)
        if finderResult.isSuccess {
            return finderResult
        }

        // Tier 4: Privileged admin move to ~/.Trash
        if allowAdminElevation {
            if case .failure(let reason) = finderResult, reason == .userCanceled {
                return .failure(reason: .userCanceled)
            }
            let adminResult = trashWithAdminPrivileges(url: url)
            if adminResult.isSuccess {
                return adminResult
            }
        }

        // Tier 5: Classify failure reason (TCC Full Disk Access vs Permission Denied)
        return classifyFailure(for: url)
    }

    /// Trashes multiple items with unified, single-prompt batch authorization for privileged moves.
    func trashBatch(
        items: [(url: URL, name: String, bytes: Int64, category: String)],
        allowAdminElevation: Bool = true
    ) -> BatchTrashSummary {
        var reports: [BatchTrashItemReport] = []
        var totalReclaimed: Int64 = 0
        var successCount = 0

        var pendingPrivilegedItems: [(url: URL, name: String, bytes: Int64, category: String)] = []

        // Stage 1: Fast non-privileged trashing (Tier 1 & 2)
        for item in items {
            guard fm.fileExists(atPath: item.url.path) else {
                reports.append(
                    BatchTrashItemReport(
                        url: item.url,
                        name: item.name,
                        bytes: item.bytes,
                        category: item.category,
                        result: .failure(reason: .fileNotFound(path: item.url.path))
                    )
                )
                continue
            }

            // Try Tier 1: Foundation trash
            do {
                try fm.trashItem(at: item.url, resultingItemURL: nil)
                totalReclaimed += item.bytes
                successCount += 1
                reports.append(
                    BatchTrashItemReport(
                        url: item.url,
                        name: item.name,
                        bytes: item.bytes,
                        category: item.category,
                        result: .success(method: .foundation)
                    )
                )
                continue
            } catch {
                // Try Tier 2: Unlock and retry
                unlockAndMakeWritable(at: item.url)
                do {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                    totalReclaimed += item.bytes
                    successCount += 1
                    reports.append(
                        BatchTrashItemReport(
                            url: item.url,
                            name: item.name,
                            bytes: item.bytes,
                            category: item.category,
                            result: .success(method: .unlockedAndTrashed)
                        )
                    )
                    continue
                } catch {
                    // Queue for single batch privileged admin execution
                    pendingPrivilegedItems.append(item)
                }
            }
        }

        // Stage 2: Unified single-prompt privileged execution for all remaining items
        if !pendingPrivilegedItems.isEmpty {
            if allowAdminElevation {
                let privilegedReports = trashBatchWithAdminPrivileges(items: pendingPrivilegedItems)
                for itemReport in privilegedReports {
                    if itemReport.result.isSuccess {
                        totalReclaimed += itemReport.bytes
                        successCount += 1
                    }
                    reports.append(itemReport)
                }
            } else {
                for item in pendingPrivilegedItems {
                    reports.append(
                        BatchTrashItemReport(
                            url: item.url,
                            name: item.name,
                            bytes: item.bytes,
                            category: item.category,
                            result: classifyFailure(for: item.url)
                        )
                    )
                }
            }
        }

        return BatchTrashSummary(
            items: reports,
            totalAttempted: items.count,
            successCount: successCount,
            reclaimedBytes: totalReclaimed
        )
    }

    // MARK: - Private Helpers

    private func unlockAndMakeWritable(at url: URL) {
        let path = url.path
        try? fm.setAttributes([.immutable: false], ofItemAtPath: path)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let childURL as URL in enumerator {
                    try? fm.setAttributes([.immutable: false], ofItemAtPath: childURL.path)
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: childURL.path)
                }
            }
        }
    }

    private func trashWithFinder(url: URL) -> TrashOperationResult {
        let escapedPath = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "Finder"
            set targetItem to POSIX file "\(escapedPath)"
            delete targetItem
        end tell
        """

        var errorDict: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        let result = script?.executeAndReturnError(&errorDict)

        if result != nil && errorDict == nil {
            return .success(method: .finderAppleScript)
        }

        if let errorDict {
            let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
            let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Finder script failed"

            if errorNumber == -128 {
                return .failure(reason: .userCanceled)
            }

            AppErrorLogService.shared.log(
                category: "TrashService",
                message: "Finder AppleScript failed for \(url.lastPathComponent) (code \(errorNumber))",
                details: errorMessage
            )
        }

        return .failure(reason: .permissionDenied(path: url.path, message: "Finder trashing could not be completed."))
    }

    private func trashWithAdminPrivileges(url: URL) -> TrashOperationResult {
        let singleReport = trashBatchWithAdminPrivileges(items: [(url: url, name: url.lastPathComponent, bytes: 0, category: "File")])
        return singleReport.first?.result ?? classifyFailure(for: url)
    }

    /// Moves a list of protected files to Trash in a SINGLE composite administrator authorization prompt.
    private func trashBatchWithAdminPrivileges(
        items: [(url: URL, name: String, bytes: Int64, category: String)]
    ) -> [BatchTrashItemReport] {
        guard !items.isEmpty else { return [] }

        let homeTrash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        let escapedTrash = homeTrash.replacingOccurrences(of: "'", with: "'\\''")

        // Build a single composite shell script that moves all items in one command
        var moveCommands: [String] = ["mkdir -p '\(escapedTrash)'"]
        for item in items {
            let escapedSource = item.url.path.replacingOccurrences(of: "'", with: "'\\''")
            moveCommands.append("mv -f '\(escapedSource)' '\(escapedTrash)/' 2>/dev/null || true")
        }

        let fullShellScript = moveCommands.joined(separator: " && ")
        let escapedShellScript = fullShellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScriptSource = """
        do shell script "\(escapedShellScript)" with administrator privileges
        """

        var errorDict: NSDictionary?
        let script = NSAppleScript(source: appleScriptSource)
        _ = script?.executeAndReturnError(&errorDict)

        var reports: [BatchTrashItemReport] = []

        if let errorDict {
            let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
            let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Administrator authorization failed"

            if errorNumber == -128 {
                for item in items {
                    reports.append(
                        BatchTrashItemReport(
                            url: item.url,
                            name: item.name,
                            bytes: item.bytes,
                            category: item.category,
                            result: .failure(reason: .userCanceled)
                        )
                    )
                }
                return reports
            }

            AppErrorLogService.shared.log(
                category: "TrashService",
                message: "Batch admin move failed for \(items.count) item(s)",
                details: errorMessage
            )
        }

        // Verify which items were successfully moved to Trash
        for item in items {
            if !fm.fileExists(atPath: item.url.path) {
                reports.append(
                    BatchTrashItemReport(
                        url: item.url,
                        name: item.name,
                        bytes: item.bytes,
                        category: item.category,
                        result: .success(method: .privilegedAdminMove)
                    )
                )
            } else {
                reports.append(
                    BatchTrashItemReport(
                        url: item.url,
                        name: item.name,
                        bytes: item.bytes,
                        category: item.category,
                        result: classifyFailure(for: item.url)
                    )
                )
            }
        }

        return reports
    }

    private func classifyFailure(for url: URL) -> TrashOperationResult {
        let path = url.path
        let home = fm.homeDirectoryForCurrentUser.path

        let protectedSubpaths = [
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Application Support",
            "\(home)/Library/Safari",
            "\(home)/Library/Cookies",
            "\(home)/Library/Suggestions",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads"
        ]

        for protected in protectedSubpaths where path.hasPrefix(protected) {
            if !FullDiskAccessService.shared.hasFullDiskAccess {
                return .failure(reason: .fullDiskAccessRequired(path: path))
            }
        }

        return .failure(
            reason: .permissionDenied(
                path: path,
                message: "macOS denied permission to move this file to Trash. Administrator or Full Disk Access permissions may be required."
            )
        )
    }
}
