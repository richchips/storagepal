import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published var report: ScanReport?
    @Published var isScanning = false
    @Published var scanMessage = "Ready when you are"
    @Published var errorMessage: String?
    @Published var selectedRecommendation: StorageRecommendation?
    @Published var launchAtLoginEnabled = false
    @Published var maintenanceRules: [MaintenanceRule] = []
    @Published var lowSpaceConfig: LowSpaceTriggerConfig = .defaultConfig
    @Published var maintenanceLogs: [MaintenanceLogEntry] = []
    @Published var installedApps: [InstalledApp] = []
    @Published var orphanedResidues: [OrphanedAppResidue] = []
    @Published var browserCacheGroups: [BrowserCacheGroup] = []
    @Published var staleLogGroups: [SystemLogGroup] = []
    @Published var localICloudCandidates: [FileCandidate] = []
    @Published var iCloudReport: ICloudUntangleReport?
    @Published var isICloudScanning = false
    @Published var permissionRecoveryContext: PermissionRecoveryContext?
    @Published var isBrowserCleanerViewPresented = false
    @Published var isQuickCleanSheetPresented = false
    @Published var quickCleanScanResult: QuickCleanScanResult?
    @Published var isQuickCleanScanning = false

    private let scanner = StorageScanner()
    private let uninstaller = AppUninstallerService()
    private let orphanedService = OrphanedResidueService()
    private let browserCleaner = BrowserCleanerService()
    private let logCleaner = SystemLogCleanerService()
    private let quickCleanService = QuickCleanService.shared
    private let photoQuality = PhotoQualityService()
    private let iCloudService = ICloudEvictionService()
    private let iCloudManager = ICloudManagerService.shared
    private let mediaCompressor = MediaCompressorService()
    let intelligenceEngine = StorageIntelligenceEngine()
    let trashService = FileTrashService.shared
    let fdaService = FullDiskAccessService.shared
    private var scanTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    var hasFullDiskAccess: Bool {
        fdaService.hasFullDiskAccess
    }

    var scanFrequency: ScanFrequency {
        get { ScanFrequency(rawValue: defaults.string(forKey: "scanFrequency") ?? "daily") ?? .daily }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: "scanFrequency")
            startScheduler()
        }
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: "notificationsEnabled") }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "notificationsEnabled")
            if newValue { requestNotificationPermission() }
        }
    }

    var lastScanDate: Date? {
        defaults.object(forKey: "lastScanDate") as? Date
    }

    var statusSymbol: String {
        switch report?.health {
        case .calm: "externaldrive.badge.checkmark"
        case .watch: "externaldrive.badge.exclamationmark"
        case .urgent: "externaldrive.badge.xmark"
        case nil: "externaldrive"
        }
    }

    init() {
        if defaults.string(forKey: "scanFrequency") == nil {
            defaults.set(ScanFrequency.daily.rawValue, forKey: "scanFrequency")
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        loadAutomationState()
    }

    deinit {
        scanTask?.cancel()
        schedulerTask?.cancel()
    }

    func start() {
        startScheduler()
        if shouldScanNow { runScan() }
    }

    func runScan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        isScanning = true
        errorMessage = nil
        scanMessage = "Starting a gentle check"

        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await scanner.scan { message in
                await self.updateScanMessage(message)
            }
            guard !Task.isCancelled else { return }
            report = self.annotateReportWithIntelligence(result)
            isScanning = false
            scanMessage = "Checked just now"
            defaults.set(result.createdAt, forKey: "lastScanDate")
            sendNotificationIfNeeded(for: result)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanMessage = "Check paused"
    }

    func open(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func handle(_ recommendation: StorageRecommendation) {
        switch recommendation.kind {
        case .trash:
            openFolder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        case .desktop:
            openFolder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
        case .iCloud:
            openICloudSettings()
        case .browserCaches:
            Task {
                await self.scanBrowserCaches()
                self.isBrowserCleanerViewPresented = true
            }
        case .oldDownloads, .largeFiles, .archive, .developerCaches, .creativeCaches, .staleProjectArtifacts, .orphanedInstallers, .staleSystemLogs:
            selectedRecommendation = recommendation
        }
    }

    func moveToTrash(_ candidate: FileCandidate) {
        moveBatchToTrash([candidate])
    }

    func moveBatchToTrash(_ candidates: [FileCandidate]) {
        guard !candidates.isEmpty else { return }
        let items = candidates.map { (url: $0.url, name: $0.name, bytes: $0.bytes, category: "File Candidate") }
        let summary = trashService.trashBatch(items: items, allowAdminElevation: true)

        let successfulPaths = Set(summary.successfulItems.map { $0.url.path })
        let removedCandidates = candidates.filter { successfulPaths.contains($0.url.path) }

        for candidate in removedCandidates {
            intelligenceEngine.recordUserAction(.trash, for: candidate)
        }

        if !removedCandidates.isEmpty {
            remove(removedCandidates)
        }

        if summary.hasFailures {
            if summary.hasPermissionFailures {
                permissionRecoveryContext = PermissionRecoveryContext(
                    title: "Permissions Needed to Trash Files",
                    subtitle: "\(summary.failedItems.count) file(s) couldn’t be moved to Trash due to macOS permission restrictions.",
                    appName: nil,
                    app: nil,
                    blockedItems: summary.failedItems,
                    onRetry: { [weak self] in
                        let remaining = candidates.filter { !successfulPaths.contains($0.url.path) }
                        self?.moveBatchToTrash(remaining)
                    }
                )
            } else {
                let errorDetails = summary.failedItems.compactMap { item -> String? in
                    if case .failure(let reason) = item.result {
                        return "“\(item.name)”: \(reason.userFacingDescription)"
                    }
                    return nil
                }
                let msg = "Some items could not be moved to Trash:\n" + errorDetails.joined(separator: "\n")
                errorMessage = msg
                AppErrorLogService.shared.log(category: "Trash", message: "Failed to move some items to Trash", details: errorDetails.joined(separator: "; "))
            }
        }
    }

    func archive(_ candidate: FileCandidate) {
        archiveBatch([candidate])
    }

    func archiveBatch(_ candidates: [FileCandidate]) {
        guard !candidates.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an archive folder"
        panel.prompt = "Move Here"
        panel.message = "Choose a folder on an external drive. The selected original files will move there."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let firstExternal = report?.externalDisks.first {
            panel.directoryURL = firstExternal.path
        }
        guard panel.runModal() == .OK, let destinationFolder = panel.url else { return }
        
        var removedCandidates: [FileCandidate] = []
        var errors: [String] = []
        for candidate in candidates {
            let destination = uniqueDestination(for: candidate.url, in: destinationFolder)
            do {
                try FileManager.default.moveItem(at: candidate.url, to: destination)
                removedCandidates.append(candidate)
                intelligenceEngine.recordUserAction(.archive, for: candidate)
            } catch {
                errors.append("“\(candidate.name)”: \(error.localizedDescription)")
            }
        }
        if !removedCandidates.isEmpty {
            remove(removedCandidates)
        }
        if !errors.isEmpty {
            let msg = "Some items could not be archived:\n" + errors.joined(separator: "\n")
            errorMessage = msg
            AppErrorLogService.shared.log(category: "Archive", message: "Failed to archive some items", details: errors.joined(separator: "; "))
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            errorMessage = "Launch at login couldn’t be changed. Ensure Storage Pal is in your Applications folder and app signatures match."
        }
    }

    func openPrivacySettings() {
        fdaService.openFullDiskAccessSettings()
    }

    func openFullDiskAccessSettings() {
        fdaService.openFullDiskAccessSettings()
    }

    func openFilesAndFoldersSettings() {
        fdaService.openFilesAndFoldersSettings()
    }

    func openStorageSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.settings.Storage")
    }

    func openICloudSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud")
    }

    private var shouldScanNow: Bool {
        guard scanFrequency != .manual else { return report == nil }
        guard let lastScanDate else { return true }
        return Date().timeIntervalSince(lastScanDate) >= scanFrequency.interval
    }

    private func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard let self else { continue }
                if self.shouldScanNow { self.runScan() }
                self.evaluateScheduledRules()
                self.evaluateLowSpaceTriggerIfNeeded()
            }
        }
    }

    func remove(_ candidate: FileCandidate) {
        remove([candidate])
    }

    func remove(_ candidates: [FileCandidate]) {
        guard let report else { return }
        let removedIDs = Set(candidates.map { $0.id })
        let totalReclaimedBytes = candidates.reduce(0) { $0 + $1.bytes }

        let updatedLargest = report.largestFiles.filter { !removedIDs.contains($0.id) }

        let updatedRecommendations = report.recommendations.compactMap { item -> StorageRecommendation? in
            let remainingCandidates = item.candidates.filter { !removedIDs.contains($0.id) }
            if remainingCandidates.isEmpty && [.oldDownloads, .largeFiles, .archive].contains(item.kind) { return nil }
            let removedItemBytes = item.candidates.filter { removedIDs.contains($0.id) }.reduce(0) { $0 + $1.bytes }
            return StorageRecommendation(
                id: item.id,
                kind: item.kind,
                title: item.title,
                detail: item.detail,
                reclaimableBytes: max(0, item.reclaimableBytes - removedItemBytes),
                candidates: remainingCandidates,
                actionLabel: item.actionLabel
            )
        }

        let updatedFolders = report.folders.map { folder -> FolderSnapshot in
            let removedInFolder = candidates.filter { $0.url.path.hasPrefix(folder.url.path) }
            guard !removedInFolder.isEmpty else { return folder }
            let bytesReclaimedInFolder = removedInFolder.reduce(0) { $0 + $1.bytes }
            let countRemoved = removedInFolder.count
            return FolderSnapshot(
                id: folder.id,
                name: folder.name,
                url: folder.url,
                bytes: max(0, folder.bytes - bytesReclaimedInFolder),
                fileCount: max(0, folder.fileCount - countRemoved),
                kind: folder.kind
            )
        }

        let updatedDisks = report.disks.map { disk -> DiskSnapshot in
            guard disk.isInternal else { return disk }
            return DiskSnapshot(
                id: disk.id,
                name: disk.name,
                path: disk.path,
                totalBytes: disk.totalBytes,
                availableBytes: min(disk.totalBytes, disk.availableBytes + totalReclaimedBytes),
                isInternal: disk.isInternal,
                isRemovable: disk.isRemovable
            )
        }

        self.report = ScanReport(
            createdAt: report.createdAt,
            disks: updatedDisks,
            folders: updatedFolders,
            largestFiles: updatedLargest,
            recommendations: updatedRecommendations,
            skippedLocations: report.skippedLocations
        )

        if let selectedRecommendation,
           let updated = updatedRecommendations.first(where: { $0.id == selectedRecommendation.id }) {
            self.selectedRecommendation = updated
        } else {
            selectedRecommendation = nil
        }
    }

    private func uniqueDestination(for source: URL, in folder: URL) -> URL {
        var destination = folder.appendingPathComponent(source.lastPathComponent)
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var index = 2
        repeat {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            destination = folder.appendingPathComponent(name)
            index += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        return destination
    }

    private func openSettingsURL(_ string: String) {
        if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if !granted || error != nil {
                Task { @MainActor in
                    self?.defaults.set(false, forKey: "notificationsEnabled")
                    self?.objectWillChange.send()
                }
            }
        }
    }

    private func updateScanMessage(_ message: String) {
        scanMessage = message
    }

    private func sendNotificationIfNeeded(for report: ScanReport) {
        guard notificationsEnabled, report.health != .calm else { return }
        let content = UNMutableNotificationContent()
        content.title = report.health.title
        if let disk = report.internalDisk {
            content.body = "\(ByteText.string(disk.availableBytes)) free. Storage Pal has \(report.recommendations.count) gentle next steps."
        } else {
            content.body = "Storage Pal found a few things worth reviewing."
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "storage-check", content: content, trigger: nil))
    }

    // MARK: - Automation & Maintenance Engine

    private func loadAutomationState() {
        let jsonDecoder = JSONDecoder()
        let home = FileManager.default.homeDirectoryForCurrentUser

        if let rulesData = defaults.data(forKey: "maintenanceRules"),
           let decoded = try? jsonDecoder.decode([MaintenanceRule].self, from: rulesData) {
            maintenanceRules = decoded
        } else {
            let downloadsURL = home.appendingPathComponent("Downloads")
            let cachesURL = home.appendingPathComponent("Library/Caches")
            maintenanceRules = [
                MaintenanceRule(
                    id: "default-downloads-trash",
                    name: "Move old downloads to Trash",
                    isEnabled: false,
                    sourceFolderURL: downloadsURL,
                    targetAction: .moveToTrash,
                    destinationFolderURL: nil,
                    schedule: .weekly,
                    minAgeDays: 30,
                    minFileBytes: 100_000_000,
                    notifyOnExecution: true,
                    lastRunDate: nil
                ),
                MaintenanceRule(
                    id: "default-caches-trash",
                    name: "Clean stale app caches",
                    isEnabled: false,
                    sourceFolderURL: cachesURL,
                    targetAction: .moveToTrash,
                    destinationFolderURL: nil,
                    schedule: .weekly,
                    minAgeDays: 14,
                    minFileBytes: 50_000_000,
                    notifyOnExecution: true,
                    lastRunDate: nil
                )
            ]
            saveMaintenanceRules()
        }

        if let configData = defaults.data(forKey: "lowSpaceConfig"),
           let decoded = try? jsonDecoder.decode(LowSpaceTriggerConfig.self, from: configData) {
            lowSpaceConfig = decoded
        } else {
            lowSpaceConfig = .defaultConfig
            saveLowSpaceConfig()
        }

        if let logsData = defaults.data(forKey: "maintenanceLogs"),
           let decoded = try? jsonDecoder.decode([MaintenanceLogEntry].self, from: logsData) {
            maintenanceLogs = decoded
        }
    }

    func saveMaintenanceRules() {
        if let encoded = try? JSONEncoder().encode(maintenanceRules) {
            defaults.set(encoded, forKey: "maintenanceRules")
        }
    }

    func saveLowSpaceConfig() {
        if let encoded = try? JSONEncoder().encode(lowSpaceConfig) {
            defaults.set(encoded, forKey: "lowSpaceConfig")
        }
    }

    func saveMaintenanceLogs() {
        if let encoded = try? JSONEncoder().encode(maintenanceLogs) {
            defaults.set(encoded, forKey: "maintenanceLogs")
        }
    }

    func addOrUpdateRule(_ rule: MaintenanceRule) {
        if let index = maintenanceRules.firstIndex(where: { $0.id == rule.id }) {
            maintenanceRules[index] = rule
        } else {
            maintenanceRules.append(rule)
        }
        saveMaintenanceRules()
    }

    func deleteRule(_ rule: MaintenanceRule) {
        maintenanceRules.removeAll { $0.id == rule.id }
        saveMaintenanceRules()
    }

    func toggleRule(_ rule: MaintenanceRule) {
        if let index = maintenanceRules.firstIndex(where: { $0.id == rule.id }) {
            maintenanceRules[index].isEnabled.toggle()
            saveMaintenanceRules()
        }
    }

    func previewRule(_ rule: MaintenanceRule) -> (candidates: [FileCandidate], totalBytes: Int64) {
        let matching = findMatchingCandidates(for: rule)
        let total = matching.reduce(0) { $0 + $1.bytes }
        return (matching, total)
    }

    func findMatchingCandidates(for rule: MaintenanceRule) -> [FileCandidate] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rule.sourceFolderURL.path) else { return [] }
        let cutoffDate = Date().addingTimeInterval(-Double(rule.minAgeDays * 24 * 60 * 60))

        guard let enumerator = fm.enumerator(
            at: rule.sourceFolderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isUbiquitousItemKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return [] }

        var results: [FileCandidate] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isUbiquitousItemKey]),
                  values.isRegularFile == true else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            guard size >= rule.minFileBytes else { continue }

            if rule.minAgeDays > 0 {
                guard let modDate = values.contentModificationDate, modDate <= cutoffDate else { continue }
            }

            results.append(
                FileCandidate(
                    id: fileURL.path,
                    url: fileURL,
                    bytes: size,
                    modifiedAt: values.contentModificationDate,
                    isCloudItem: values.isUbiquitousItem ?? false
                )
            )
        }
        return results.sorted { $0.bytes > $1.bytes }
    }

    func calculateFolderSize(url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
               vals.isRegularFile == true {
                total += Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
            }
        }
        return total
    }

    func getMountedExternalVolumes() -> [(name: String, path: String, freeBytes: Int64, totalBytes: Int64)] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsRemovableKey]
        guard let volumeURLs = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }

        var results: [(name: String, path: String, freeBytes: Int64, totalBytes: Int64)] = []
        for url in volumeURLs {
            guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isInternal = vals.volumeIsInternal ?? true
            let name = vals.volumeName ?? url.lastPathComponent
            let total = Int64(vals.volumeTotalCapacity ?? 0)
            let free = Int64(vals.volumeAvailableCapacityForImportantUsage ?? 0)

            // If not root / internal boot volume, or explicitly removable
            if (!isInternal || vals.volumeIsRemovable == true) && url.path != "/" && total > 0 {
                results.append((name: name, path: url.path, freeBytes: free, totalBytes: total))
            }
        }
        return results
    }

    func executeRule(_ rule: MaintenanceRule, triggerReason: RuleTriggerReason = .manual) {
        let matching = findMatchingCandidates(for: rule)
        if matching.isEmpty {
            recordLogEntry(
                ruleName: rule.name,
                actionDescription: "No matching files met criteria.",
                processedCount: 0,
                reclaimedBytes: 0,
                isLowSpace: triggerReason == .lowSystemStorage(thresholdGB: lowSpaceConfig.thresholdGB),
                triggerReason: triggerReason,
                error: nil
            )
            return
        }

        var processedCount = 0
        var reclaimedBytes: Int64 = 0
        var errorMessages: [String] = []

        switch rule.targetAction {
        case .moveToTrash:
            let items = matching.map { (url: $0.url, name: $0.name, bytes: $0.bytes, category: "Maintenance Rule: \(rule.name)") }
            let summary = trashService.trashBatch(items: items, allowAdminElevation: false)
            processedCount = summary.successCount
            reclaimedBytes = summary.reclaimedBytes
            if summary.hasFailures {
                errorMessages = summary.failedItems.compactMap { item in
                    if case .failure(let reason) = item.result {
                        return "“\(item.name)”: \(reason.userFacingDescription)"
                    }
                    return nil
                }
            }

        case .moveToExternalDrive, .archiveToFolder, .copyToExternalDrive:
            guard let destFolder = rule.destinationFolderURL else {
                recordLogEntry(
                    ruleName: rule.name,
                    actionDescription: "Operation skipped",
                    processedCount: 0,
                    reclaimedBytes: 0,
                    isLowSpace: false,
                    triggerReason: triggerReason,
                    error: "No destination folder/external drive specified."
                )
                return
            }

            guard FileManager.default.fileExists(atPath: destFolder.path) else {
                recordLogEntry(
                    ruleName: rule.name,
                    actionDescription: "Operation deferred",
                    processedCount: 0,
                    reclaimedBytes: 0,
                    isLowSpace: false,
                    triggerReason: triggerReason,
                    error: "Target external drive or folder is not connected/mounted at \(destFolder.path)."
                )
                return
            }

            // Determine destination directory (optionally organized by year-month)
            let finalTargetDir: URL
            if rule.organizeByYearMonth {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM"
                let dateSubfolderName = formatter.string(from: Date())
                finalTargetDir = destFolder.appendingPathComponent(dateSubfolderName, isDirectory: true)
                try? FileManager.default.createDirectory(at: finalTargetDir, withIntermediateDirectories: true)
            } else {
                finalTargetDir = destFolder
            }

            for candidate in matching {
                let dest = uniqueDestination(for: candidate.url, in: finalTargetDir)
                do {
                    if rule.targetAction == .copyToExternalDrive {
                        try FileManager.default.copyItem(at: candidate.url, to: dest)
                        processedCount += 1
                        reclaimedBytes += candidate.bytes
                    } else {
                        // Move across volumes: copy then delete source
                        if candidate.url.pathComponents.first != dest.pathComponents.first {
                            try FileManager.default.copyItem(at: candidate.url, to: dest)
                            try? FileManager.default.removeItem(at: candidate.url)
                        } else {
                            try FileManager.default.moveItem(at: candidate.url, to: dest)
                        }
                        processedCount += 1
                        reclaimedBytes += candidate.bytes
                    }
                } catch {
                    errorMessages.append("“\(candidate.name)”: \(error.localizedDescription)")
                }
            }
        }

        if processedCount > 0 && rule.targetAction != .copyToExternalDrive {
            remove(Array(matching.prefix(processedCount)))
        }

        var updatedRule = rule
        updatedRule.lastRunDate = Date()
        addOrUpdateRule(updatedRule)

        let errorText = errorMessages.isEmpty ? nil : errorMessages.joined(separator: "; ")
        let actionDesc = "\(rule.targetAction.title): Processed \(processedCount) items (\(ByteText.string(reclaimedBytes))) [\(triggerReason.displayLabel)]"

        recordLogEntry(
            ruleName: rule.name,
            actionDescription: actionDesc,
            processedCount: processedCount,
            reclaimedBytes: reclaimedBytes,
            isLowSpace: false,
            triggerReason: triggerReason,
            error: errorText
        )

        if rule.notifyOnExecution && notificationsEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Storage Pal Automation: \(rule.name)"
            content.body = "Transferred \(processedCount) file(s) (\(ByteText.string(reclaimedBytes))) • \(triggerReason.displayLabel)."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rule-\(rule.id)-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
        }
    }

    func executeRule(_ rule: MaintenanceRule, isLowSpaceTrigger: Bool) {
        executeRule(rule, triggerReason: isLowSpaceTrigger ? .lowSystemStorage(thresholdGB: lowSpaceConfig.thresholdGB) : .manual)
    }

    func evaluateScheduledRules() {
        let now = Date()
        for rule in maintenanceRules where rule.isEnabled {
            // Check 1: Folder size limit trigger
            if rule.enableFolderSizeTrigger {
                let currentFolderBytes = calculateFolderSize(url: rule.sourceFolderURL)
                if currentFolderBytes >= rule.folderSizeLimitBytes {
                    let currentGB = Double(currentFolderBytes) / 1_000_000_000.0
                    executeRule(rule, triggerReason: .folderSizeExceeded(currentSizeGB: currentGB, limitGB: rule.folderSizeLimitGB))
                    continue
                }
            }

            // Check 2: Time schedule trigger
            if rule.schedule != .manual {
                let lastRun = rule.lastRunDate ?? .distantPast
                if now.timeIntervalSince(lastRun) >= rule.schedule.interval {
                    executeRule(rule, triggerReason: .scheduled(schedule: rule.schedule.rawValue))
                }
            }
        }
    }

    func evaluateLowSpaceTriggerIfNeeded() {
        guard lowSpaceConfig.isEnabled,
              let internalDisk = report?.internalDisk,
              internalDisk.totalBytes > 0 else { return }

        let freeGB = Double(internalDisk.availableBytes) / (1024 * 1024 * 1024)
        guard freeGB < lowSpaceConfig.thresholdGB else { return }

        let now = Date()
        let lastTrigger = lowSpaceConfig.lastTriggeredDate ?? .distantPast
        guard now.timeIntervalSince(lastTrigger) >= 3600 else { return }

        lowSpaceConfig.lastTriggeredDate = now
        saveLowSpaceConfig()

        if lowSpaceConfig.autoExecuteRules {
            for rule in maintenanceRules where rule.isEnabled {
                executeRule(rule, triggerReason: .lowSystemStorage(thresholdGB: lowSpaceConfig.thresholdGB))
            }
        }

        if notificationsEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Low Storage Alert"
            content.body = "Internal drive storage is at \(String(format: "%.1f", freeGB)) GB (below \(Int(lowSpaceConfig.thresholdGB)) GB threshold)."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-space-alert-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
        }
    }

    private func recordLogEntry(
        ruleName: String,
        actionDescription: String,
        processedCount: Int,
        reclaimedBytes: Int64,
        isLowSpace: Bool,
        triggerReason: RuleTriggerReason? = nil,
        error: String?
    ) {
        let entry = MaintenanceLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            ruleName: ruleName,
            actionDescription: actionDescription,
            filesProcessedCount: processedCount,
            reclaimedBytes: reclaimedBytes,
            wasTriggeredByLowSpace: isLowSpace,
            triggerReason: triggerReason,
            errorDetails: error
        )
        maintenanceLogs.insert(entry, at: 0)
        if maintenanceLogs.count > 50 {
            maintenanceLogs = Array(maintenanceLogs.prefix(50))
        }
        saveMaintenanceLogs()
    }

    func annotateReportWithIntelligence(_ rawReport: ScanReport) -> ScanReport {
        let scoredRecs = rawReport.recommendations.map { rec -> StorageRecommendation in
            let scoredCandidates = rec.candidates.map { cand -> FileCandidate in
                var updated = cand
                updated.confidenceScore = intelligenceEngine.confidenceScore(for: cand)
                return updated
            }
            var updatedRec = StorageRecommendation(
                id: rec.id,
                kind: rec.kind,
                title: rec.title,
                detail: rec.detail,
                reclaimableBytes: rec.reclaimableBytes,
                candidates: scoredCandidates,
                actionLabel: rec.actionLabel,
                confidenceScore: rec.confidenceScore
            )
            updatedRec.confidenceScore = intelligenceEngine.confidenceScore(for: updatedRec)
            return updatedRec
        }

        return ScanReport(
            createdAt: rawReport.createdAt,
            disks: rawReport.disks,
            folders: rawReport.folders,
            largestFiles: rawReport.largestFiles.map { cand in
                var updated = cand
                updated.confidenceScore = intelligenceEngine.confidenceScore(for: cand)
                return updated
            },
            recommendations: scoredRecs,
            skippedLocations: rawReport.skippedLocations
        )
    }

    // MARK: - Smart App Uninstaller

    func scanInstalledApps() {
        Task {
            let apps = await uninstaller.scanInstalledApps()
            self.installedApps = apps
        }
    }

    func uninstallApp(_ app: InstalledApp) {
        var itemsToTrash: [(url: URL, name: String, bytes: Int64, category: String)] = []
        itemsToTrash.append((url: app.appURL, name: app.name, bytes: app.appSizeBytes, category: "Application Bundle"))
        for leftover in app.leftovers {
            itemsToTrash.append((url: leftover.url, name: "\(app.name) (\(leftover.category))", bytes: leftover.bytes, category: leftover.category))
        }

        let summary = trashService.trashBatch(items: itemsToTrash, allowAdminElevation: true)

        let successfulPaths = Set(summary.successfulItems.map { $0.url.path })
        let bundleRemoved = successfulPaths.contains(app.appURL.path)
        let remainingLeftovers = app.leftovers.filter { !successfulPaths.contains($0.url.path) }

        if bundleRemoved && remainingLeftovers.isEmpty {
            installedApps.removeAll { $0.id == app.id }
        } else if bundleRemoved {
            if let index = installedApps.firstIndex(where: { $0.id == app.id }) {
                installedApps[index] = InstalledApp(
                    id: app.id,
                    name: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    appURL: app.appURL,
                    appSizeBytes: 0,
                    leftovers: remainingLeftovers
                )
            }
        } else {
            if let index = installedApps.firstIndex(where: { $0.id == app.id }) {
                installedApps[index] = InstalledApp(
                    id: app.id,
                    name: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    appURL: app.appURL,
                    appSizeBytes: app.appSizeBytes,
                    leftovers: remainingLeftovers
                )
            }
        }

        let entry = MaintenanceLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            ruleName: "App Uninstall: \(app.name)",
            actionDescription: "Uninstalled \(summary.successCount) of \(summary.totalAttempted) item(s) (\(ByteText.string(summary.reclaimedBytes)) reclaimed)",
            filesProcessedCount: summary.successCount,
            reclaimedBytes: summary.reclaimedBytes,
            wasTriggeredByLowSpace: false,
            errorDetails: summary.hasFailures ? summary.failedItems.map { "\($0.name): \($0.result)" }.joined(separator: "; ") : nil
        )
        maintenanceLogs.insert(entry, at: 0)
        saveMaintenanceLogs()

        if summary.hasFailures {
            if summary.hasPermissionFailures {
                permissionRecoveryContext = PermissionRecoveryContext(
                    title: "Permissions Needed to Uninstall “\(app.name)”",
                    subtitle: "macOS restricted access to \(summary.failedItems.count) item(s). Grant Full Disk Access in Settings or authorize the action.",
                    appName: app.name,
                    app: app,
                    blockedItems: summary.failedItems,
                    onRetry: { [weak self] in
                        self?.uninstallApp(app)
                    }
                )
            } else {
                let errorDetails = summary.failedItems.compactMap { item -> String? in
                    if case .failure(let reason) = item.result {
                        return "“\(item.name)”: \(reason.userFacingDescription)"
                    }
                    return nil
                }
                errorMessage = "Some files could not be uninstalled:\n" + errorDetails.joined(separator: "\n")
            }
        }
    }

    // MARK: - Phase 3: iCloud Eviction & Untangler

    func scanICloudStorage() {
        guard !isICloudScanning else { return }
        isICloudScanning = true
        Task {
            let report = await iCloudManager.scanICloudStorage()
            let candidates = await iCloudService.findLocalICloudCandidates()
            self.iCloudReport = report
            self.localICloudCandidates = candidates
            self.isICloudScanning = false
        }
    }

    func scanLocalICloudCandidates() {
        scanICloudStorage()
    }

    func evictICloudFolder(_ folder: ICloudFolderNode) {
        Task {
            do {
                let (count, bytes) = try await iCloudManager.evictFolder(at: folder.url)
                scanICloudStorage()

                let entry = MaintenanceLogEntry(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    ruleName: "iCloud Folder Eviction: \(folder.name)",
                    actionDescription: "Evicted \(count) local files in folder to cloud (\(ByteText.string(bytes)))",
                    filesProcessedCount: count,
                    reclaimedBytes: bytes,
                    wasTriggeredByLowSpace: false,
                    errorDetails: nil
                )
                self.maintenanceLogs.insert(entry, at: 0)
                self.saveMaintenanceLogs()
            } catch {
                self.errorMessage = "Could not evict folder “\(folder.name)”: \(error.localizedDescription)"
            }
        }
    }

    func evictAllDownloadedICloudFiles() {
        guard let report = iCloudReport, !report.downloadedFiles.isEmpty else { return }
        Task {
            var totalReclaimed: Int64 = 0
            var count = 0
            for item in report.downloadedFiles {
                do {
                    let bytes = try await iCloudManager.evictFile(at: item.url)
                    totalReclaimed += bytes
                    count += 1
                } catch {}
            }
            scanICloudStorage()

            let entry = MaintenanceLogEntry(
                id: UUID().uuidString,
                timestamp: Date(),
                ruleName: "iCloud Batch Eviction",
                actionDescription: "Evicted \(count) downloaded files across iCloud Drive (\(ByteText.string(totalReclaimed)))",
                filesProcessedCount: count,
                reclaimedBytes: totalReclaimed,
                wasTriggeredByLowSpace: false,
                errorDetails: nil
            )
            self.maintenanceLogs.insert(entry, at: 0)
            self.saveMaintenanceLogs()
        }
    }

    func trashICloudClutter(items: [ICloudClutterItem]) {
        Task {
            let tuples = items.map { (url: $0.url, name: $0.name, bytes: $0.bytes, category: $0.kind.rawValue) }
            let summary = trashService.trashBatch(items: tuples)
            scanICloudStorage()

            if summary.hasFailures {
                self.errorMessage = "Moved \(summary.successCount) clutter item(s) to Trash, but \(summary.failedItems.count) failed."
            }
        }
    }

    func downloadICloudFile(_ item: ICloudFileItem) {
        Task {
            do {
                try await iCloudManager.downloadItem(at: item.url)
                scanICloudStorage()
            } catch {
                self.errorMessage = "Could not start downloading “\(item.name)”: \(error.localizedDescription)"
            }
        }
    }

    func evictFromLocalSSD(_ candidate: FileCandidate) {
        Task {
            do {
                let reclaimed = try await iCloudService.evictItem(at: candidate.url)
                self.localICloudCandidates.removeAll { $0.id == candidate.id }
                self.remove([candidate])
                scanICloudStorage()

                let entry = MaintenanceLogEntry(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    ruleName: "iCloud Eviction: \(candidate.name)",
                    actionDescription: "Evicted local copy to iCloud cloud storage (\(ByteText.string(reclaimed)))",
                    filesProcessedCount: 1,
                    reclaimedBytes: reclaimed,
                    wasTriggeredByLowSpace: false,
                    errorDetails: nil
                )
                self.maintenanceLogs.insert(entry, at: 0)
                self.saveMaintenanceLogs()
            } catch {
                self.errorMessage = "Could not evict “\(candidate.name)” from local SSD: \(error.localizedDescription)"
            }
        }
    }

    func compressMedia(_ candidate: FileCandidate) {
        Task {
            do {
                let result = try await mediaCompressor.compressFile(at: candidate.url, progress: { _ in })
                self.remove([candidate])

                let entry = MaintenanceLogEntry(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    ruleName: "Media Compressor: \(candidate.name)",
                    actionDescription: "Compressed media file (\(ByteText.string(result.reclaimedBytes)) saved)",
                    filesProcessedCount: 1,
                    reclaimedBytes: result.reclaimedBytes,
                    wasTriggeredByLowSpace: false,
                    errorDetails: nil
                )
                self.maintenanceLogs.insert(entry, at: 0)
                self.saveMaintenanceLogs()
            } catch {
                self.errorMessage = "Could not compress “\(candidate.name)”: \(error.localizedDescription)"
                AppErrorLogService.shared.log(category: "MediaCompressor", message: "Failed to compress \(candidate.name)", details: error.localizedDescription)
            }
        }
    }

    func copyErrorLogs() {
        AppErrorLogService.shared.copyLogsToClipboard()
    }

    func copyActiveError() {
        if let errorMessage {
            AppErrorLogService.shared.copyTextToClipboard(errorMessage)
        }
    }

    // MARK: - CCleaner Pro Expansion Methods

    func scanOrphanedResidues() {
        Task {
            let residues = await orphanedService.scanOrphanedResidues()
            self.orphanedResidues = residues
        }
    }

    func trashOrphanedResidues(_ residues: [OrphanedAppResidue]) {
        guard !residues.isEmpty else { return }
        let items = residues.map { (url: $0.url, name: $0.name, bytes: $0.bytes, category: $0.category) }
        let summary = trashService.trashBatch(items: items, allowAdminElevation: true)

        let successfulPaths = Set(summary.successfulItems.map { $0.url.path })
        self.orphanedResidues.removeAll { successfulPaths.contains($0.id) }

        let entry = MaintenanceLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            ruleName: "Orphaned App Residue Cleanup",
            actionDescription: "Cleaned \(summary.successCount) orphaned support folder(s) (\(ByteText.string(summary.reclaimedBytes)) reclaimed)",
            filesProcessedCount: summary.successCount,
            reclaimedBytes: summary.reclaimedBytes,
            wasTriggeredByLowSpace: false,
            errorDetails: summary.hasFailures ? summary.failedItems.map { "\($0.name): \($0.result)" }.joined(separator: "; ") : nil
        )
        maintenanceLogs.insert(entry, at: 0)
        saveMaintenanceLogs()

        if summary.hasFailures {
            if summary.hasPermissionFailures {
                permissionRecoveryContext = PermissionRecoveryContext(
                    title: "Permissions Needed to Trash Orphaned Leftovers",
                    subtitle: "macOS restricted access to \(summary.failedItems.count) leftover item(s). Grant Full Disk Access in Settings or authorize the action.",
                    appName: "Orphaned Residue",
                    app: nil,
                    blockedItems: summary.failedItems,
                    onRetry: { [weak self] in
                        self?.trashOrphanedResidues(residues)
                    }
                )
            } else {
                errorMessage = "Some orphaned leftovers could not be moved to Trash."
            }
        }
    }

    func scanBrowserCaches() async {
        let groups = await browserCleaner.scanBrowserCaches()
        self.browserCacheGroups = groups
    }

    func cleanBrowserCache(_ group: BrowserCacheGroup) async {
        let reclaimed = await browserCleaner.cleanCache(for: group)
        self.browserCacheGroups.removeAll { $0.id == group.id }

        let entry = MaintenanceLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            ruleName: "Browser Cache Cleanup: \(group.browser.rawValue)",
            actionDescription: "Cleared disposable web cache and media buffers (\(ByteText.string(reclaimed)) reclaimed)",
            filesProcessedCount: group.fileCount,
            reclaimedBytes: reclaimed,
            wasTriggeredByLowSpace: false,
            errorDetails: nil
        )
        maintenanceLogs.insert(entry, at: 0)
        saveMaintenanceLogs()
    }

    func scanStaleLogs() async {
        let groups = await logCleaner.scanStaleLogs()
        self.staleLogGroups = groups
    }

    func cleanStaleLogs(_ group: SystemLogGroup) async {
        let reclaimed = await logCleaner.cleanStaleLogs(in: group)
        self.staleLogGroups.removeAll { $0.id == group.id }

        let entry = MaintenanceLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            ruleName: "System Log Cleanup: \(group.name)",
            actionDescription: "Cleaned stale crash dumps and diagnostic logs (\(ByteText.string(reclaimed)) reclaimed)",
            filesProcessedCount: group.fileCount,
            reclaimedBytes: reclaimed,
            wasTriggeredByLowSpace: false,
            errorDetails: nil
        )
        maintenanceLogs.insert(entry, at: 0)
        saveMaintenanceLogs()
    }

    // MARK: - Quick Clean Orchestration

    func startQuickCleanFlow() {
        isQuickCleanSheetPresented = true
        if quickCleanScanResult == nil && !isQuickCleanScanning {
            Task {
                await runQuickScan()
            }
        }
    }

    func runQuickScan() async {
        isQuickCleanScanning = true
        let result = await quickCleanService.scanQuickCleanTargets()
        self.quickCleanScanResult = result
        self.isQuickCleanScanning = false
    }

    func executeQuickClean(selectedItems: [QuickCleanItem]) async -> QuickCleanSummary {
        let summary = await quickCleanService.executeQuickClean(items: selectedItems)

        let selectedIDs = Set(selectedItems.map { $0.id })
        if let currentResult = quickCleanScanResult {
            let remainingItems = currentResult.items.filter { !selectedIDs.contains($0.id) }
            self.quickCleanScanResult = QuickCleanScanResult(createdAt: Date(), items: remainingItems)
        }

        let entry = MaintenanceLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            ruleName: "Quick Free Up Space",
            actionDescription: "Cleaned \(summary.cleanedItemsCount) items (\(ByteText.string(summary.reclaimedBytes)) reclaimed)",
            filesProcessedCount: summary.cleanedItemsCount,
            reclaimedBytes: summary.reclaimedBytes,
            wasTriggeredByLowSpace: false,
            errorDetails: summary.failedCount > 0 ? "\(summary.failedCount) item(s) skipped or required elevated permissions" : nil
        )
        maintenanceLogs.insert(entry, at: 0)
        saveMaintenanceLogs()

        // Trigger background refresh so dashboard storage charts and recommendations update
        runScan()

        return summary
    }
}


