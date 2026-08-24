import AppKit
import Foundation

enum TrashMethod: String, Sendable {
    case foundation = "Standard Trash"
    case unlockedAndTrashed = "Unlocked & Trashed"
    case finderAppleScript = "Finder System Trash"
    case privilegedAdminMove = "Admin Authorized Move"
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
        // Finder can prompt the user with standard Touch ID / Admin password dialog for /Applications items.
        let finderResult = trashWithFinder(url: url)
        if finderResult.isSuccess {
            return finderResult
        }

        // Tier 4: Privileged admin move to ~/.Trash (if allowed and not canceled)
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

    /// Trashes multiple items and produces a comprehensive summary.
    func trashBatch(
        items: [(url: URL, name: String, bytes: Int64, category: String)],
        allowAdminElevation: Bool = true
    ) -> BatchTrashSummary {
        var reports: [BatchTrashItemReport] = []
        var totalReclaimed: Int64 = 0
        var successCount = 0

        for item in items {
            let result = trashItem(at: item.url, allowAdminElevation: allowAdminElevation)
            if result.isSuccess {
                totalReclaimed += item.bytes
                successCount += 1
            }
            reports.append(
                BatchTrashItemReport(
                    url: item.url,
                    name: item.name,
                    bytes: item.bytes,
                    category: item.category,
                    result: result
                )
            )
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
        // Attempt to remove immutable flags (uchg, schg) via POSIX / Foundation
        try? fm.setAttributes([.immutable: false], ofItemAtPath: path)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)

        // For directories, also attempt unlocking immediate children
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

            // Error -128 is "User canceled"
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
        let homeTrash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        let escapedSource = url.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedTrash = homeTrash.replacingOccurrences(of: "'", with: "'\\''")

        // Safe non-destructive admin move into user's ~/.Trash folder
        let shellScript = "mkdir -p '\(escapedTrash)' && mv -f '\(escapedSource)' '\(escapedTrash)/'"
        let escapedShellScript = shellScript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let appleScriptSource = """
        do shell script "\(escapedShellScript)" with administrator privileges
        """

        var errorDict: NSDictionary?
        let script = NSAppleScript(source: appleScriptSource)
        let result = script?.executeAndReturnError(&errorDict)

        if result != nil && errorDict == nil {
            return .success(method: .privilegedAdminMove)
        }

        if let errorDict {
            let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
            let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Administrator authorization failed"

            if errorNumber == -128 {
                return .failure(reason: .userCanceled)
            }

            AppErrorLogService.shared.log(
                category: "TrashService",
                message: "Admin AppleScript move failed for \(url.lastPathComponent) (code \(errorNumber))",
                details: errorMessage
            )
        }

        return classifyFailure(for: url)
    }

    private func classifyFailure(for url: URL) -> TrashOperationResult {
        let path = url.path
        let home = fm.homeDirectoryForCurrentUser.path

        // Check if path is in TCC-protected directories
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
