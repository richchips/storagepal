import AppKit
import Foundation

@MainActor
final class FullDiskAccessService: ObservableObject {
    static let shared = FullDiskAccessService()

    @Published private(set) var hasFullDiskAccess: Bool = false
    private var observer: NSObjectProtocol?

    private init() {
        self.hasFullDiskAccess = Self.probeFullDiskAccess()
        startObservingAppActivation()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Re-evaluates Full Disk Access status immediately and updates published state.
    @discardableResult
    func refreshStatus() -> Bool {
        let granted = Self.probeFullDiskAccess()
        if self.hasFullDiskAccess != granted {
            self.hasFullDiskAccess = granted
        }
        return granted
    }

    /// Deep-links to macOS System Settings -> Privacy & Security -> Full Disk Access
    func openFullDiskAccessSettings() {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for str in urlStrings {
            if let url = URL(string: str), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Deep-links to macOS System Settings -> Privacy & Security -> Files and Folders
    func openFilesAndFoldersSettings() {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for str in urlStrings {
            if let url = URL(string: str), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    // MARK: - Internal Probing

    /// Probes TCC-protected locations to determine if Full Disk Access is active.
    static func probeFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // Test candidates known to be protected by macOS TCC privacy subsystem
        let testLocations = [
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Suggestions"),
            home.appendingPathComponent("Library/Cookies")
        ]

        for location in testLocations {
            guard fm.fileExists(atPath: location.path) else { continue }
            do {
                _ = try fm.contentsOfDirectory(atPath: location.path)
                return true
            } catch let error as NSError {
                // Cocoa error 257 (NSFileReadNoPermissionError) or POSIX error 1 (EPERM)
                if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                    return false
                }
                if error.domain == NSPOSIXErrorDomain && error.code == 1 {
                    return false
                }
            }
        }

        // If none of the protected folders exist, check if we can list ~/Library
        let libraryURL = home.appendingPathComponent("Library")
        return (try? fm.contentsOfDirectory(atPath: libraryURL.path)) != nil
    }

    private func startObservingAppActivation() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }
}
