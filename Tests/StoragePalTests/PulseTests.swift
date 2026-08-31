import XCTest
@testable import StoragePal

final class PulseTests: XCTestCase {
    func testUnavailableAndManualChecksNeverCountAsVerifiedOrHealthy() {
        let report = PulseReport(createdAt: Date(), checks: [
            PulseCheck(area: .storage, state: .clear, detail: "", metric: ""),
            PulseCheck(area: .cleanup, state: .review, detail: "", metric: ""),
            PulseCheck(area: .firewall, state: .unavailable, detail: "", metric: ""),
            PulseCheck(area: .updates, state: .manual, detail: "", metric: "")
        ])
        XCTAssertEqual(report.verifiedCount, 2)
        XCTAssertEqual(report.reviewCount, 1)
        XCTAssertEqual(report.unverifiedCount, 2)
        let unknown = PulseReport(createdAt: Date(), checks: [report.checks[2], report.checks[3]])
        XCTAssertEqual(unknown.headline, "A few checks still need you.")
    }

    func testStorageRequiresValidMeasurementsAndUsesBothThresholds() {
        XCTAssertEqual(PulseService.storageCheck(total: nil, available: nil).state, .unavailable)
        XCTAssertEqual(PulseService.storageCheck(total: 0, available: 0).state, .unavailable)
        XCTAssertEqual(PulseService.storageCheck(total: 100, available: 101).state, .unavailable)
        XCTAssertEqual(PulseService.storageCheck(total: 100, available: -1).state, .unavailable)
        XCTAssertEqual(PulseService.storageCheck(total: 100_000_000_000, available: 19_000_000_000).state, .review)
        XCTAssertEqual(PulseService.storageCheck(total: 1_000_000_000_000, available: 90_000_000_000).state, .review)
        XCTAssertEqual(PulseService.storageCheck(total: 200_000_000_000, available: 20_000_000_000).state, .clear)
    }

    func testSecurityDoesNotGuessFromErrorsOrTransitions() {
        XCTAssertEqual(PulseService.securityCheck(area: .encryption, output: "FileVault is On.\n", status: 0).state, .clear)
        XCTAssertEqual(PulseService.securityCheck(area: .encryption, output: "FileVault is Off.", status: 0).state, .review)
        XCTAssertEqual(PulseService.securityCheck(area: .encryption, output: "FileVault is On.", status: 1).state, .unavailable)
        XCTAssertEqual(PulseService.securityCheck(area: .encryption, output: "Encryption in progress: 40%", status: 0).state, .unavailable)
        XCTAssertEqual(PulseService.securityCheck(area: .firewall, output: "Firewall is enabled. (State = 1)\n", status: 0).state, .clear)
        XCTAssertEqual(PulseService.securityCheck(area: .firewall, output: "Firewall is disabled. (State = 0)", status: 0).state, .review)
        XCTAssertEqual(PulseService.securityCheck(area: .firewall, output: "Permission denied", status: 0).state, .unavailable)
    }

    func testActivityAcceptsMulticoreCPUAndRejectsInvalidSamples() throws {
        let app = PulseAppIdentity(pid: 42, name: "Fixture", bundleURL: URL(fileURLWithPath: "/Applications/Fixture.app"), launchDate: Date(), isBackground: false)
        let output = "1 0.0 10\n42 235.5 1048576\nnot a process\n42 nan 10\n42 0.0 9223372036854775807\n"
        let rows = try PulseService.parseActivity(output, apps: [app])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cpuPercent, 235.5)
        XCTAssertEqual(rows[0].residentBytes, 1_073_741_824)
        XCTAssertTrue(rows[0].warrantsReview)
        XCTAssertThrowsError(try PulseService.parseActivity("", apps: [app]))
        XCTAssertThrowsError(try PulseService.parseActivity("42 -1 100", apps: [app]))
        XCTAssertThrowsError(try PulseService.parseActivity("1 0.0 10", apps: [app]))
    }

    func testCacheScanExcludesUserDataSymlinksAndTrash() async throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("PulseTests-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/Google/Chrome")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let cacheFile = cache.appendingPathComponent("cached-image")
        try Data(repeating: 7, count: 8192).write(to: cacheFile)
        let privateFile = home.appendingPathComponent("Documents/keep.txt")
        try fm.createDirectory(at: privateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("private".utf8).write(to: privateFile)
        try fm.createSymbolicLink(at: cache.appendingPathComponent("linked-file"), withDestinationURL: privateFile)
        try fm.createSymbolicLink(at: cache.appendingPathComponent("linked-folder"), withDestinationURL: privateFile.deletingLastPathComponent())
        for relative in [".Trash/keep", "Library/Application Support/Google/Chrome/Default/Cookies", "Library/Application Support/Google/Chrome/Default/History"] {
            let url = home.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("untouched".utf8).write(to: url)
        }
        let result = try await PulseService().scanCaches(home: home)
        // FileManager may normalize /var to /private/var during enumeration.
        XCTAssertEqual(result.candidates.map { $0.url.lastPathComponent }, ["cached-image"])
        XCTAssertTrue(fm.contentsEqual(atPath: result.candidates[0].url.path, andPath: cacheFile.path))
        XCTAssertTrue(result.limitations.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: cacheFile.path), "Scanning must not remove files")
        XCTAssertEqual(try String(contentsOf: privateFile, encoding: .utf8), "private")
        let limited = try await PulseService().scanCaches(home: home, entryLimit: 0)
        XCTAssertFalse(limited.limitations.isEmpty, "A truncated scan must not appear complete")
    }

    func testCancelledCacheScanDoesNotPublishPartialSuccess() async throws {
        let service = PulseService()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.scanCaches()
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
}
