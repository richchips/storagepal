import XCTest
@testable import StoragePal

final class StoragePalTests: XCTestCase {

    func testByteTextFormatting() {
        let bytesMB: Int64 = 50 * 1024 * 1024
        let resultMB = ByteText.string(bytesMB)
        XCTAssertTrue(resultMB.contains("50") || resultMB.contains("52"), "Expected formatted byte string to include formatted megabytes count: \(resultMB)")

        let bytesGB: Int64 = 5 * 1024 * 1024 * 1024
        let resultGB = ByteText.string(bytesGB)
        XCTAssertTrue(resultGB.contains("5") || resultGB.contains("GB"), "Expected formatted byte string to contain GB unit: \(resultGB)")
    }

    func testStorageHealthThresholds() {
        let diskCalm = DiskSnapshot(
            id: "/mock",
            name: "Macintosh HD",
            path: URL(fileURLWithPath: "/"),
            totalBytes: 500_000_000_000,
            availableBytes: 200_000_000_000,
            isInternal: true,
            isRemovable: false
        )
        let reportCalm = ScanReport(
            createdAt: Date(),
            disks: [diskCalm],
            folders: [],
            largestFiles: [],
            recommendations: [],
            skippedLocations: []
        )
        XCTAssertEqual(reportCalm.health, .calm)

        let diskWatch = DiskSnapshot(
            id: "/mock",
            name: "Macintosh HD",
            path: URL(fileURLWithPath: "/"),
            totalBytes: 500_000_000_000,
            availableBytes: 20_000_000_000,
            isInternal: true,
            isRemovable: false
        )
        let reportWatch = ScanReport(
            createdAt: Date(),
            disks: [diskWatch],
            folders: [],
            largestFiles: [],
            recommendations: [],
            skippedLocations: []
        )
        XCTAssertEqual(reportWatch.health, .watch)

        let diskUrgent = DiskSnapshot(
            id: "/mock",
            name: "Macintosh HD",
            path: URL(fileURLWithPath: "/"),
            totalBytes: 500_000_000_000,
            availableBytes: 5_000_000_000,
            isInternal: true,
            isRemovable: false
        )
        let reportUrgent = ScanReport(
            createdAt: Date(),
            disks: [diskUrgent],
            folders: [],
            largestFiles: [],
            recommendations: [],
            skippedLocations: []
        )
        XCTAssertEqual(reportUrgent.health, .urgent)
    }

    func testPotentialSavingsCalculation() {
        let file1 = FileCandidate(
            id: "/Users/test/Downloads/video.mp4",
            url: URL(fileURLWithPath: "/Users/test/Downloads/video.mp4"),
            bytes: 1_000_000_000,
            modifiedAt: Date().addingTimeInterval(-60 * 24 * 60 * 60),
            isCloudItem: false
        )
        let file2 = FileCandidate(
            id: "/Users/test/Downloads/archive.zip",
            url: URL(fileURLWithPath: "/Users/test/Downloads/archive.zip"),
            bytes: 500_000_000,
            modifiedAt: Date().addingTimeInterval(-40 * 24 * 60 * 60),
            isCloudItem: false
        )

        let rec1 = StorageRecommendation(
            id: "rec1",
            kind: .oldDownloads,
            title: "Old Downloads",
            detail: "Test",
            reclaimableBytes: 1_500_000_000,
            candidates: [file1, file2],
            actionLabel: "Review"
        )
        // rec2 contains file1 again - should not be double counted
        let rec2 = StorageRecommendation(
            id: "rec2",
            kind: .largeFiles,
            title: "Large Files",
            detail: "Test",
            reclaimableBytes: 1_000_000_000,
            candidates: [file1],
            actionLabel: "Review"
        )

        let report = ScanReport(
            createdAt: Date(),
            disks: [],
            folders: [],
            largestFiles: [file1, file2],
            recommendations: [rec1, rec2],
            skippedLocations: []
        )

        XCTAssertEqual(report.potentialSavings, 1_500_000_000)
    }

    @MainActor
    func testDynamicCandidateRemovalUpdates() {
        let model = AppModel()
        let disk = DiskSnapshot(
            id: "/",
            name: "Macintosh HD",
            path: URL(fileURLWithPath: "/"),
            totalBytes: 500_000_000_000,
            availableBytes: 100_000_000_000,
            isInternal: true,
            isRemovable: false
        )
        let folder = FolderSnapshot(
            id: "downloads",
            name: "Downloads",
            url: URL(fileURLWithPath: "/Users/test/Downloads"),
            bytes: 2_000_000_000,
            fileCount: 5,
            kind: .downloads
        )
        let candidate = FileCandidate(
            id: "/Users/test/Downloads/large.iso",
            url: URL(fileURLWithPath: "/Users/test/Downloads/large.iso"),
            bytes: 1_000_000_000,
            modifiedAt: Date(),
            isCloudItem: false
        )
        let rec = StorageRecommendation(
            id: "large-files",
            kind: .largeFiles,
            title: "Check large files",
            detail: "Test",
            reclaimableBytes: 1_000_000_000,
            candidates: [candidate],
            actionLabel: "Review"
        )
        model.report = ScanReport(
            createdAt: Date(),
            disks: [disk],
            folders: [folder],
            largestFiles: [candidate],
            recommendations: [rec],
            skippedLocations: []
        )

        model.remove(candidate)

        XCTAssertNotNil(model.report)
        XCTAssertEqual(model.report?.internalDisk?.availableBytes, 101_000_000_000)
        XCTAssertEqual(model.report?.folders.first?.bytes, 1_000_000_000)
        XCTAssertEqual(model.report?.folders.first?.fileCount, 4)
        XCTAssertTrue(model.report?.largestFiles.isEmpty ?? false)
    }

    @MainActor
    func testMaintenanceRuleMatchingAndPreview() {
        let model = AppModel()
        let rule = MaintenanceRule(
            id: "test-rule",
            name: "Test Rule",
            isEnabled: true,
            sourceFolderURL: URL(fileURLWithPath: "/tmp"),
            targetAction: .moveToTrash,
            destinationFolderURL: nil,
            schedule: .weekly,
            minAgeDays: 0,
            minFileBytes: 1_000,
            notifyOnExecution: false,
            lastRunDate: nil
        )

        model.addOrUpdateRule(rule)
        XCTAssertTrue(model.maintenanceRules.contains(where: { $0.id == "test-rule" }))

        let (candidates, totalBytes) = model.previewRule(rule)
        XCTAssertGreaterThanOrEqual(totalBytes, 0)
        XCTAssertGreaterThanOrEqual(candidates.count, 0)

        model.deleteRule(rule)
        XCTAssertFalse(model.maintenanceRules.contains(where: { $0.id == "test-rule" }))
    }

    @MainActor
    func testLowSpaceTriggerEvaluation() {
        let model = AppModel()
        model.lowSpaceConfig = LowSpaceTriggerConfig(
            isEnabled: true,
            thresholdGB: 50.0,
            autoExecuteRules: false,
            lastTriggeredDate: nil
        )

        let diskLow = DiskSnapshot(
            id: "/",
            name: "Macintosh HD",
            path: URL(fileURLWithPath: "/"),
            totalBytes: 500_000_000_000,
            availableBytes: 10_000_000_000,
            isInternal: true,
            isRemovable: false
        )

        model.report = ScanReport(
            createdAt: Date(),
            disks: [diskLow],
            folders: [],
            largestFiles: [],
            recommendations: [],
            skippedLocations: []
        )

        model.evaluateLowSpaceTriggerIfNeeded()
        XCTAssertNotNil(model.lowSpaceConfig.lastTriggeredDate)
    }

    @MainActor
    func testStorageIntelligenceEngine() {
        let engine = StorageIntelligenceEngine()
        let candidate = FileCandidate(
            id: "/Users/test/Library/Developer/Xcode/DerivedData/Build.tmp",
            url: URL(fileURLWithPath: "/Users/test/Library/Developer/Xcode/DerivedData/Build.tmp"),
            bytes: 500_000_000,
            modifiedAt: Date().addingTimeInterval(-90 * 24 * 3600),
            isCloudItem: false
        )

        let initialScore = engine.confidenceScore(for: candidate)
        XCTAssertGreaterThan(initialScore, 0.50)

        let initialActions = engine.model.totalActionsRecorded
        engine.recordUserAction(.trash, for: candidate)
        XCTAssertEqual(engine.model.totalActionsRecorded, initialActions + 1)
    }

    func testDeveloperScannerInstantiation() async {
        let scanner = DeveloperScanner()
        let result = await scanner.scan()
        XCTAssertGreaterThanOrEqual(result.totalBytes, 0)
    }

    func testAppUninstallerServiceInstantiation() async {
        let service = AppUninstallerService()
        let apps = await service.scanInstalledApps()
        XCTAssertGreaterThanOrEqual(apps.count, 0)
    }

    func testICloudEvictionServiceInstantiation() async {
        let service = ICloudEvictionService()
        let items = await service.findLocalICloudCandidates()
        XCTAssertGreaterThanOrEqual(items.count, 0)
    }

    func testMediaCompressorServiceCanCompress() async {
        let compressor = MediaCompressorService()
        let canCompressMP4 = await compressor.canCompress(URL(fileURLWithPath: "/test/sample.mp4"))
        let canCompressPDF = await compressor.canCompress(URL(fileURLWithPath: "/test/sample.pdf"))
        let canCompressTXT = await compressor.canCompress(URL(fileURLWithPath: "/test/sample.txt"))

        XCTAssertTrue(canCompressMP4)
        XCTAssertTrue(canCompressPDF)
        XCTAssertFalse(canCompressTXT)
    }

    func testTreemapBuilderLayout() {
        let node1 = TreemapNode(id: "1", name: "Large", url: URL(fileURLWithPath: "/1"), bytes: 100_000, isDirectory: false, children: [])
        let node2 = TreemapNode(id: "2", name: "Small", url: URL(fileURLWithPath: "/2"), bytes: 50_000, isDirectory: false, children: [])

        let laidOut = TreemapBuilder.layout(nodes: [node1, node2], in: CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(laidOut.count, 2)
        XCTAssertGreaterThan(laidOut[0].rect.width * laidOut[0].rect.height, 0)
    }

    func testPhotoDeduplicatorServiceInstantiation() async {
        let service = PhotoDeduplicatorService()
        let duplicates = await service.findDuplicates()
        XCTAssertGreaterThanOrEqual(duplicates.count, 0)
    }

    func testDuplicateFinderServiceInstantiation() async {
        let service = DuplicateFinderService()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let results = await service.scanDuplicates(in: home.appendingPathComponent("Downloads"), minSizeBytes: 10_000_000)
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }

    @MainActor
    func testAppErrorLogService() {
        let logger = AppErrorLogService.shared
        logger.log(category: "Test", message: "Test diagnostic message", details: "Sample details")
        XCTAssertFalse(logger.logs.isEmpty)
        XCTAssertEqual(logger.logs.first?.category, "Test")
    }

    @MainActor
    func testFullDiskAccessServiceProbe() {
        let fdaService = FullDiskAccessService.shared
        _ = fdaService.refreshStatus()
        // Ensure probing runs without crashing and reflects a boolean status
        XCTAssertNotNil(fdaService.hasFullDiskAccess)
    }

    @MainActor
    func testFileTrashServiceFileNotFound() {
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_storage_pal_file_\(UUID().uuidString).tmp")
        let result = FileTrashService.shared.trashItem(at: missingURL)
        if case .failure(let reason) = result {
            XCTAssertEqual(reason, .fileNotFound(path: missingURL.path))
        } else {
            XCTFail("Expected fileNotFound failure for missing URL")
        }
    }

    @MainActor
    func testFileTrashServiceSafeTrashing() {
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let testFile = testDir.appendingPathComponent("test_trash_sample.txt")
        try? "Storage Pal safe trashing test".data(using: .utf8)?.write(to: testFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))

        let result = FileTrashService.shared.trashItem(at: testFile)
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))

        try? FileManager.default.removeItem(at: testDir)
    }

    @MainActor
    func testBatchTrashSummaryClassification() {
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_\(UUID().uuidString)")
        let report = BatchTrashItemReport(
            url: missingURL,
            name: "Missing",
            bytes: 500,
            category: "Test",
            result: .failure(reason: .fullDiskAccessRequired(path: missingURL.path))
        )
        let summary = BatchTrashSummary(items: [report], totalAttempted: 1, successCount: 0, reclaimedBytes: 0)
        XCTAssertTrue(summary.hasFailures)
        XCTAssertTrue(summary.hasPermissionFailures)
    }

    func testOrphanedResidueService() async {
        let service = OrphanedResidueService()
        let residues = await service.scanOrphanedResidues()
        XCTAssertGreaterThanOrEqual(residues.count, 0)
    }

    @MainActor
    func testStartupManagerService() async {
        let service = StartupManagerService.shared
        let items = await service.scanStartupItems()
        XCTAssertGreaterThanOrEqual(items.count, 0)
    }

    func testBrowserCleanerService() async {
        let service = BrowserCleanerService()
        let caches = await service.scanBrowserCaches()
        XCTAssertGreaterThanOrEqual(caches.count, 0)
        for cache in caches {
            XCTAssertGreaterThan(cache.bytes, 0)
            XCTAssertFalse(cache.browser.rawValue.isEmpty)
        }
    }

    func testSystemLogCleanerService() async {
        let service = SystemLogCleanerService()
        let logs = await service.scanStaleLogs(olderThanDays: 1)
        XCTAssertGreaterThanOrEqual(logs.count, 0)
    }

    func testPhotoQualityService() async {
        let service = PhotoQualityService()
        let screenshots = await service.scanScreenshots(olderThanDays: 1)
        XCTAssertGreaterThanOrEqual(screenshots.count, 0)
        let lowQuality = await service.scanLowQualityPhotos()
        XCTAssertGreaterThanOrEqual(lowQuality.count, 0)
    }

    func testMetadataSanitizerInspection() async {
        let service = MetadataSanitizerService()
        let tempDir = FileManager.default.temporaryDirectory
        let sampleFile = tempDir.appendingPathComponent("sample_test_\(UUID().uuidString).txt")
        try? "Test content".data(using: .utf8)?.write(to: sampleFile)

        let report = await service.inspectMetadata(for: sampleFile)
        XCTAssertFalse(report.hasGPS)
        XCTAssertEqual(report.tagsCount, 0)

        try? FileManager.default.removeItem(at: sampleFile)
    }

    func testSecureShredderDestruction() async {
        let service = SecureShredderService()
        let tempDir = FileManager.default.temporaryDirectory
        let sampleFile = tempDir.appendingPathComponent("shred_test_\(UUID().uuidString).dat")
        try? "Top secret confidential data".data(using: .utf8)?.write(to: sampleFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sampleFile.path))
        try? await service.shredFile(at: sampleFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sampleFile.path))
    }

    @MainActor
    func testStorageSentinelService() {
        let service = StorageSentinelService.shared
        service.recordSnapshot()
        let forecast = service.calculateForecast()
        XCTAssertFalse(forecast.velocityStatus.isEmpty)
    }

    func testDriveConsolidatorService() async {
        let service = DriveConsolidatorService()
        let tempDir = FileManager.default.temporaryDirectory
        let results = await service.scanCrossVolumeDuplicates(directories: [tempDir], minSizeBytes: 10_000_000)
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }

    func testLocalArchivalHubService() async {
        let service = LocalArchivalHubService()
        let subscriptions = await service.scanCloudSubscriptions()
        XCTAssertEqual(subscriptions.count, 4)
        let shares = await service.scanNetworkAndExternalShares()
        XCTAssertGreaterThanOrEqual(shares.count, 0)
    }

    func testDocumentRedactionEngineFinancialMatching() async {
        let engine = DocumentRedactionEngine()
        let sampleText = "The employee with SSN 123-45-6789 received a total compensation of $145,000.00 into account GB82WEST12345698765432."
        let matches = await engine.scanText(text: sampleText, template: .financial)
        XCTAssertGreaterThanOrEqual(matches.count, 2)

        let tokenized = await engine.redactText(originalText: sampleText, matches: matches, mode: .aiTokenSwap)
        XCTAssertFalse(tokenized.contains("123-45-6789"))
        XCTAssertFalse(tokenized.contains("$145,000.00"))
        XCTAssertTrue(tokenized.contains("[SSN_1]"))
        XCTAssertTrue(tokenized.contains("[AMOUNT_1]"))
    }

    @MainActor
    func testAITokenSwapRoundTrip() async {
        let engine = DocumentRedactionEngine()
        let tokenService = AITokenSwapService.shared

        let originalDoc = "Party: Acme Corp agreed to a confidential settlement of $500,000 under Case No. CV-2026-99."
        let matches = await engine.scanText(text: originalDoc, template: .legal)

        let session = tokenService.createSession(documentName: "TestAgreement.txt", template: .legal, matches: matches)
        let aiPrompt = await engine.redactText(originalText: originalDoc, matches: matches, mode: .aiTokenSwap)

        // Simulated AI response using the tokens
        let simulatedAIResponse = "Summary of Case: [PARTY_1] reached an agreement regarding [SETTLEMENT_1] in [CASE_ID_1]."
        let (restored, count) = tokenService.restoreRealData(aiResponseText: simulatedAIResponse, session: session)

        XCTAssertGreaterThan(count, 0)
        XCTAssertTrue(restored.contains("Acme Corp"))
        XCTAssertTrue(restored.contains("$500,000"))
        XCTAssertFalse(restored.contains("[PARTY_1]"))
        XCTAssertFalse(restored.contains("[SETTLEMENT_1]"))

        tokenService.deleteSession(id: session.id)
    }

    @MainActor
    func testClipboardGuardDetection() {
        let guardService = ClipboardGuardService.shared
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sk-test1234567890abcdef1234567890", forType: .string)
        guardService.inspectClipboard()

        XCTAssertNotNil(guardService.detectedSensitiveItem)
        XCTAssertEqual(guardService.detectedSensitiveItem?.kind, .openAIKey)

        guardService.sanitizeClipboard()
        XCTAssertNil(guardService.detectedSensitiveItem)
        let sanitized = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(sanitized.contains("sk-***"))
    }

    func testAIPromptFormatting() async {
        let engine = DocumentRedactionEngine()
        let prompt = engine.generateAIPrompt(
            role: .legal,
            documentName: "Contract.pdf",
            tokenizedText: "Party [PARTY_1] agrees to terms."
        )
        XCTAssertTrue(prompt.contains("expert legal contract counsel"))
        XCTAssertTrue(prompt.contains("Contract.pdf"))
        XCTAssertTrue(prompt.contains("[PARTY_1]"))
    }

    func testManualBoxPDFRedactionModel() {
        let box = ManualRedactionBox(id: UUID(), rectNormalized: [0.1, 0.2, 0.3, 0.4], pageIndex: 1)
        XCTAssertEqual(box.rectNormalized.count, 4)
        XCTAssertEqual(box.pageIndex, 1)
    }

    func testSemanticVersionComparison() {
        XCTAssertTrue(AppUpdateService.isVersion("0.14.0", greaterThan: "0.13.0"))
        XCTAssertTrue(AppUpdateService.isVersion("1.0.0", greaterThan: "0.9.9"))
        XCTAssertTrue(AppUpdateService.isVersion("0.13.1", greaterThan: "0.13.0"))
        XCTAssertTrue(AppUpdateService.isVersion("v0.14.0", greaterThan: "0.13.0"))
        XCTAssertFalse(AppUpdateService.isVersion("0.13.0", greaterThan: "0.13.0"))
        XCTAssertFalse(AppUpdateService.isVersion("0.12.0", greaterThan: "0.13.0"))
    }

    @MainActor
    func testAppUpdateServiceStatusFlow() async {
        let updateService = AppUpdateService.shared
        XCTAssertFalse(updateService.currentVersion.isEmpty)
        await updateService.checkForUpdates(userInitiated: true)
        XCTAssertNotNil(updateService.lastCheckDate)
        XCTAssertTrue(updateService.status == .upToDate(currentVersion: updateService.currentVersion) || {
            if case .updateAvailable = updateService.status { return true }
            return false
        }())
    }

    // MARK: - Clinical De-Identification QA Benchmarks

    func testClinicalDirectNameDetection() async {
        let engine = DocumentRedactionEngine()
        var entityMap: [String: String] = [:]
        var counters: [String: Int] = [:]

        let sample = "Client Sam R. attended initial psychology assessment with Dr. Jane Doe."
        let matches = await engine.scanText(
            text: sample,
            template: .clinicalPsychology,
            policy: .internalClinical,
            sharedEntityTokenMap: &entityMap,
            tokenCounters: &counters
        )

        let names = matches.filter { $0.category.contains("Name") || $0.category.contains("Person") }
        XCTAssertTrue(names.contains(where: { $0.originalText.contains("Sam R.") }), "Sam R. must be detected as a direct identifier.")
        XCTAssertTrue(names.contains(where: { $0.originalText.contains("Dr. Jane Doe") || $0.originalText.contains("Jane Doe") }), "Dr. Jane Doe must be detected.")

        let tokenized = await engine.redactText(originalText: sample, matches: matches, mode: .aiTokenSwap)
        XCTAssertFalse(tokenized.contains("Sam R."), "Direct name 'Sam R.' must be replaced by a token.")
        XCTAssertTrue(tokenized.contains("[PERSON_1]"))
    }

    func testClinicalCommonWordPrecision() async {
        let engine = DocumentRedactionEngine()
        var entityMap: [String: String] = [:]
        var counters: [String: Int] = [:]

        let sample = "Footer: Fictional training material - not a real clinical record"
        let matches = await engine.scanText(
            text: sample,
            template: .clinicalPsychology,
            policy: .internalClinical,
            sharedEntityTokenMap: &entityMap,
            tokenCounters: &counters
        )

        XCTAssertFalse(matches.contains(where: { $0.originalText.lowercased() == "record" }), "'record' must never trigger a false-positive patient ID.")
        XCTAssertEqual(matches.count, 0, "Common footer text should produce zero false positives.")
    }

    func testClinicalDosagePreservation() async {
        let engine = DocumentRedactionEngine()
        var entityMap: [String: String] = [:]
        var counters: [String: Int] = [:]

        let sample = "Currently prescribed sertraline 50 mg by GP, started around 7 weeks ago. PHQ-9 score 14."
        let matches = await engine.scanText(
            text: sample,
            template: .clinicalPsychology,
            policy: .internalClinical,
            sharedEntityTokenMap: &entityMap,
            tokenCounters: &counters
        )

        let tokenized = await engine.redactText(originalText: sample, matches: matches, mode: .aiTokenSwap)
        XCTAssertTrue(tokenized.contains("sertraline 50 mg"), "Medication dosage must be preserved for clinical formulation.")
        XCTAssertTrue(tokenized.contains("PHQ-9 score 14"), "Psychometric scores must remain intact.")
    }

    func testQuasiIdentifierHandlingByPolicy() async {
        let engine = DocumentRedactionEngine()

        let sample = "Assessment on Date 25/08/2026 for client aged Age 36."

        // Internal Clinical Mode (Quasi-identifiers preserved)
        var mapInternal: [String: String] = [:]
        var countersInternal: [String: Int] = [:]
        let matchesInternal = await engine.scanText(
            text: sample,
            template: .clinicalPsychology,
            policy: .internalClinical,
            sharedEntityTokenMap: &mapInternal,
            tokenCounters: &countersInternal
        )
        let tokenizedInternal = await engine.redactText(originalText: sample, matches: matchesInternal, mode: .aiTokenSwap)
        XCTAssertTrue(tokenizedInternal.contains("25/08/2026"), "Internal mode preserves exact date.")
        XCTAssertTrue(tokenizedInternal.contains("36"), "Internal mode preserves exact age.")

        // External Research Mode (Quasi-identifiers tokenized)
        var mapStrict: [String: String] = [:]
        var countersStrict: [String: Int] = [:]
        let matchesStrict = await engine.scanText(
            text: sample,
            template: .clinicalPsychology,
            policy: .externalResearch,
            sharedEntityTokenMap: &mapStrict,
            tokenCounters: &countersStrict
        )
        let tokenizedStrict = await engine.redactText(originalText: sample, matches: matchesStrict, mode: .aiTokenSwap)
        XCTAssertFalse(tokenizedStrict.contains("25/08/2026"), "Strict mode tokenizes exact date.")
        XCTAssertTrue(tokenizedStrict.contains("[DATE_1]"))
        XCTAssertTrue(tokenizedStrict.contains("[AGE_1]"))
    }

    func testEntityConsistencyAndIdempotency() async {
        let engine = DocumentRedactionEngine()
        var entityMap: [String: String] = [:]
        var counters: [String: Int] = [:]

        let sample = "Client Sam R. met with counselor. Sam R. reported mood improvement. Later, Sam R. completed review."
        let matches = await engine.scanText(
            text: sample,
            template: .clinicalPsychology,
            policy: .internalClinical,
            sharedEntityTokenMap: &entityMap,
            tokenCounters: &counters
        )

        let tokenized = await engine.redactText(originalText: sample, matches: matches, mode: .aiTokenSwap)
        XCTAssertEqual(counters["PERSON"], 1, "Repeated occurrences of 'Sam R.' must use the same token [PERSON_1].")
        XCTAssertFalse(tokenized.contains("Sam R."))
        XCTAssertTrue(tokenized.contains("[PERSON_1]"))

        // Idempotency: scanning already tokenized text
        var entityMap2: [String: String] = [:]
        var counters2: [String: Int] = [:]
        let secondPassMatches = await engine.scanText(
            text: tokenized,
            template: .clinicalPsychology,
            policy: .internalClinical,
            sharedEntityTokenMap: &entityMap2,
            tokenCounters: &counters2
        )
        XCTAssertEqual(secondPassMatches.count, 0, "Sanitizer must be idempotent on existing bracketed tokens.")
    }

    // MARK: - AI Watermark & Steganography Tests

    func testZeroWidthWatermarkDetectionAndRemoval() async {
        let service = AIWatermarkSanitizerService()

        // Text embedded with Zero-Width Space (U+200B), Non-Joiner (U+200C), BOM (U+FEFF), and Variation Selector (U+FE0F)
        let watermarkedText = "This\u{200B} is a\u{200C} watermarked\u{FEFF} essay generated\u{FE0F} by LLM."
        let report = await service.analyzeAndSanitize(text: watermarkedText, sourceName: "TestSnippet")

        XCTAssertEqual(report.invisibleCharactersCount, 4, "Must detect all 4 invisible watermarking characters.")
        XCTAssertEqual(report.purifiedText, "This is a watermarked essay generated by LLM.", "Purified text must be completely stripped of zero-width markers.")
        XCTAssertTrue(report.rawWithVisualMarkers.contains("[ZW-SPACE]"))
        XCTAssertTrue(report.rawWithVisualMarkers.contains("[ZW-NJ]"))
        XCTAssertTrue(report.rawWithVisualMarkers.contains("[ZW-BOM]"))
        XCTAssertTrue(report.rawWithVisualMarkers.contains("[VS-TAG]"))
    }

    func testHomoglyphLookalikeNormalization() async {
        let service = AIWatermarkSanitizerService()

        // Cyrillic 'а' (U+0430), 'е' (U+0435), 'о' (U+043E), 'р' (U+0440) substituted into English words
        let homoglyphText = "Th\u{0435} quick br\u{043E}wn f\u{043E}x jum\u{0440}s \u{0430}cross."
        let report = await service.analyzeAndSanitize(text: homoglyphText, sourceName: "TestHomoglyph")

        XCTAssertEqual(report.homoglyphsCount, 5, "Must detect 5 Cyrillic confusable lookalikes.")
        XCTAssertEqual(report.purifiedText, "The quick brown fox jumps across.", "Must normalize Cyrillic lookalikes back to standard Latin ASCII.")
    }

    func testAIChatbotPreambleAndPostambleRemoval() async {
        let service = AIWatermarkSanitizerService()

        let aiGeneratedResponse = """
        Certainly! Here is the summary of the quarterly financial report:

        Revenue grew 14% year-over-year while operating expenses declined 3%.

        I hope this helps! Let me know if you need anything else.
        """

        let report = await service.analyzeAndSanitize(text: aiGeneratedResponse, sourceName: "ChatGPTSummary")

        XCTAssertTrue(report.aiSignaturesCount >= 2, "Must detect both preamble and postamble.")
        XCTAssertFalse(report.purifiedText.contains("Certainly! Here is the summary"), "Must strip intro preamble.")
        XCTAssertFalse(report.purifiedText.contains("I hope this helps!"), "Must strip outro disclaimer.")
        XCTAssertTrue(report.purifiedText.contains("Revenue grew 14% year-over-year while operating expenses declined 3%."))
    }

    func testCleanTextPreservationFidelity() async {
        let service = AIWatermarkSanitizerService()

        let normalHumanText = "Clean natural text written by a human without watermarks, zero-width characters, or lookalikes."
        let report = await service.analyzeAndSanitize(text: normalHumanText, sourceName: "HumanDoc")

        XCTAssertEqual(report.totalWatermarksFound, 0)
        XCTAssertEqual(report.invisibleCharactersCount, 0)
        XCTAssertEqual(report.homoglyphsCount, 0)
        XCTAssertEqual(report.aiSignaturesCount, 0)
        XCTAssertEqual(report.steganographyConfidencePercent, 0)
        XCTAssertEqual(report.purifiedText, normalHumanText, "Human text must remain 100% byte-for-byte identical.")
    }

    func testStatisticalTokenBiasAndClicheNeutralization() async {
        let service = AIWatermarkSanitizerService()

        let aiText = "Furthermore, it is crucial to delve into the rich tapestry of renewable energy solutions; however, navigating the complexities remains pivotal for growth."
        let initialMetrics = await service.analyzeStatisticalWatermark(text: aiText)

        XCTAssertTrue(initialMetrics.detectedAIKeywords.contains("delve into") || initialMetrics.detectedAIKeywords.contains("crucial") || initialMetrics.detectedAIKeywords.contains("rich tapestry"))

        let result = await service.neutralizeTokenBias(text: aiText, level: .balanced)

        XCTAssertFalse(result.purifiedText.contains("delve into"), "AI buzzword 'delve into' must be replaced.")
        XCTAssertFalse(result.purifiedText.contains("rich tapestry"), "AI cliché 'rich tapestry' must be neutralized.")
        XCTAssertFalse(result.purifiedText.contains("crucial"), "'crucial' must be replaced by a natural synonym.")
        XCTAssertTrue(result.perturbations.count >= 3, "Must produce token perturbations to break n-gram hash chains.")
        XCTAssertTrue(result.metrics.aiVocabularyDensityPercent < initialMetrics.aiVocabularyDensityPercent)
    }

    func testSentenceBurstinessCalculation() async {
        let service = AIWatermarkSanitizerService()

        // Text with uniform sentence lengths (typical LLM output)
        let uniformAIText = "The team evaluated the primary system performance metrics. The results demonstrated a clear increase in speed. All stakeholders agreed on the upcoming quarterly plan."
        let uniformMetrics = await service.analyzeStatisticalWatermark(text: uniformAIText)
        XCTAssertTrue(uniformMetrics.burstinessScore < 3.0, "Uniform sentence lengths should yield low burstiness variance.")

        // Natural human text with high sentence length variance (burstiness)
        let naturalText = "Yes. When the quarterly benchmark results finally came in after weeks of exhaustive testing across all three production clusters, we noticed something unexpected. Revenue soared."
        let naturalMetrics = await service.analyzeStatisticalWatermark(text: naturalText)
        XCTAssertTrue(naturalMetrics.burstinessScore > 6.0, "Natural text with short and long sentences should yield high burstiness variance.")
    }

    func testICloudUntanglerScanExecution() async {
        let service = ICloudManagerService.shared
        let report = await service.scanICloudStorage()

        XCTAssertNotNil(report)
        XCTAssertTrue(report.totalICloudBytes >= 0)
        XCTAssertTrue(report.totalLocalSSDBytes >= 0)
        XCTAssertTrue(report.totalEvictedCloudBytes >= 0)
    }

    @MainActor
    func testFolderSizeLimitTriggerAndExternalDriveMove() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("StoragePalTest_\(UUID().uuidString)")
        let sourceDir = tempDir.appendingPathComponent("SourceFolder")
        let destDir = tempDir.appendingPathComponent("ExternalDriveMock")

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create sample test files
        let file1 = sourceDir.appendingPathComponent("big_archive.zip")
        let dummyData = Data(repeating: 0x41, count: 10_000)
        try dummyData.write(to: file1)

        let file2 = sourceDir.appendingPathComponent("test_doc.pdf")
        try dummyData.write(to: file2)

        let model = AppModel()
        let calculatedSize = model.calculateFolderSize(url: sourceDir)
        XCTAssertEqual(calculatedSize, 20_000)

        // Create rule to move files to destDir
        let rule = MaintenanceRule(
            id: "test-ext-rule",
            name: "Archive to Mock Drive",
            isEnabled: true,
            sourceFolderURL: sourceDir,
            targetAction: .moveToExternalDrive,
            destinationFolderURL: destDir,
            schedule: .daily,
            minAgeDays: 0,
            minFileBytes: 0,
            notifyOnExecution: false,
            lastRunDate: nil,
            enableFolderSizeTrigger: true,
            folderSizeLimitGB: 0.00001, // ~10KB threshold
            organizeByYearMonth: true
        )

        model.executeRule(rule, triggerReason: .folderSizeExceeded(currentSizeGB: 0.00002, limitGB: 0.00001))

        // Verify files moved to destination subfolder
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let dateFolder = destDir.appendingPathComponent(formatter.string(from: Date()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dateFolder.path))

        let destFile1 = dateFolder.appendingPathComponent("big_archive.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile1.path))

        // Verify source files are cleared
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path))

        // Verify log was recorded
        XCTAssertTrue(model.maintenanceLogs.contains { $0.ruleName == "Archive to Mock Drive" })
    }
}



