import Foundation
import Darwin

/// Local, read-only checks. No shell interpolation, network requests, or mutations.
actor PulseService {
    private let fm = FileManager.default

    func storageCheck() -> PulseCheck {
        do {
            let values = try fm.homeDirectoryForCurrentUser.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityKey
            ])
            return Self.storageCheck(total: values.volumeTotalCapacity.map(Int64.init),
                                     available: values.volumeAvailableCapacity.map(Int64.init))
        } catch {
            return Self.storageCheck(total: nil, available: nil)
        }
    }

    nonisolated static func storageCheck(total: Int64?, available: Int64?) -> PulseCheck {
        guard let total, let available, total > 0, available >= 0, available <= total else {
            return PulseCheck(area: .storage, state: .unavailable,
                              detail: "The current storage capacity could not be read.", metric: "Not measured")
        }
        let fraction = Double(available) / Double(total)
        let crowded = fraction < 0.10 || available < 20_000_000_000
        return PulseCheck(area: .storage, state: crowded ? .review : .clear,
                          detail: "\(Int(fraction * 100))% available on your home volume. Pulse suggests reviewing space below 10% or 20 GB free.",
                          metric: "\(ByteText.string(available)) free")
    }

    /// Only regular, locally downloaded files in disposable browser cache roots.
    /// No cookies, history, app support, Trash, packages, or symlink traversal.
    func scanCaches(home: URL? = nil, entryLimit: Int = 30_000) throws -> PulseCacheScan {
        let root = home ?? fm.homeDirectoryForCurrentUser
        let relativePaths = [
            "Library/Caches/com.apple.Safari",
            "Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari",
            "Library/Caches/Google/Chrome", "Library/Caches/BraveSoftware/Brave-Browser",
            "Library/Caches/Firefox/Profiles", "Library/Caches/Microsoft Edge",
            "Library/Caches/com.operasoftware.Opera"
        ]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
                                       .isUbiquitousItemKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                       .contentModificationDateKey]
        var candidates: [FileCandidate] = []
        var limitations: [String] = []
        var visited = Set<String>()
        var entries = 0
        let deadline = Date().addingTimeInterval(20)
        for relativePath in relativePaths {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(relativePath)
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
                    limitations.append(relativePath)
                    continue
                }
            } catch {
                if !Self.isMissingFile(error) { limitations.append(relativePath) }
                continue
            }
            var hadError = false
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                 options: [.skipsPackageDescendants],
                                                 errorHandler: { _, _ in hadError = true; return true }) else {
                limitations.append(relativePath)
                continue
            }
            while let file = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                entries += 1
                if entries > entryLimit || Date() > deadline {
                    limitations.append("Scan limit reached; additional cache files were not measured.")
                    return PulseCacheScan(candidates: candidates, limitations: limitations)
                }
                do {
                    let values = try file.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true || values.isUbiquitousItem == true {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard values.isRegularFile == true, visited.insert(file.standardizedFileURL.path).inserted else { continue }
                    let bytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    guard bytes > 0 else { continue }
                    candidates.append(FileCandidate(id: file.path, url: file, bytes: bytes,
                                                    modifiedAt: values.contentModificationDate, isCloudItem: false))
                } catch { hadError = true }
            }
            if hadError { limitations.append(relativePath) }
        }
        return PulseCacheScan(candidates: candidates.sorted { $0.bytes > $1.bytes }, limitations: limitations)
    }

    nonisolated static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return true }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    }

    func activity(for apps: [PulseAppIdentity]) async throws -> [PulseAppActivity] {
        let result = try await run("/bin/ps", arguments: ["-axo", "pid=,pcpu=,rss="], timeout: 8)
        guard result.status == 0 else { throw PulseError.unavailable }
        return try Self.parseActivity(result.output, apps: apps)
    }

    nonisolated static func parseActivity(_ output: String, apps: [PulseAppIdentity]) throws -> [PulseAppActivity] {
        let identities = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [Int32: PulseAppActivity] = [:]
        var validRows = 0
        for line in output.split(separator: "\n") {
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count == 3, let pid = Int32(columns[0]), pid > 0,
                  let cpu = Double(columns[1]), cpu.isFinite, cpu >= 0,
                  let kib = Int64(columns[2]), kib >= 0, kib <= Int64.max / 1024 else { continue }
            validRows += 1
            if let app = identities[pid] {
                rows[pid] = PulseAppActivity(app: app, cpuPercent: cpu, residentBytes: kib * 1024)
            }
        }
        guard validRows > 0, apps.isEmpty || !rows.isEmpty else { throw PulseError.unavailable }
        return rows.values.sorted {
            if $0.warrantsReview != $1.warrantsReview { return $0.warrantsReview }
            if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
            return $0.residentBytes > $1.residentBytes
        }
    }

    func securityChecks() async throws -> [PulseCheck] {
        var checks: [PulseCheck] = []
        for (area, path, arguments) in [
            (PulseArea.encryption, "/usr/bin/fdesetup", ["status"]),
            (PulseArea.firewall, "/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        ] {
            try Task.checkCancellation()
            do {
                let result = try await run(path, arguments: arguments, timeout: 5)
                checks.append(Self.securityCheck(area: area, output: result.output, status: result.status))
            } catch is CancellationError { throw CancellationError() }
            catch { checks.append(Self.securityCheck(area: area, output: "", status: -1)) }
        }
        return checks
    }

    nonisolated static func securityCheck(area: PulseArea, output: String, status: Int32) -> PulseCheck {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled: Bool?
        if status != 0 { enabled = nil }
        else if area == .encryption {
            // Transitional or unfamiliar output must never count as a pass.
            enabled = text == "FileVault is On." ? true : text == "FileVault is Off." ? false : nil
        } else {
            enabled = text == "Firewall is enabled. (State = 1)" ? true :
                text == "Firewall is disabled. (State = 0)" ? false : nil
        }
        guard let enabled else {
            return PulseCheck(area: area, state: .unavailable,
                              detail: "This setting could not be verified. Check its current status in System Settings.", metric: "Not verified")
        }
        let detail = area == .encryption
            ? "FileVault helps protect data if your device is lost. This checks its reported status, not hardware health."
            : "The firewall controls incoming network connections. Review your needs before changing this setting."
        return PulseCheck(area: area, state: enabled ? .clear : .review, detail: detail, metric: enabled ? "Enabled" : "Disabled")
    }

    private func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> (output: String, status: Int32) {
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        pipe.fileHandleForWriting.closeFile()
        // Drain while the process runs, so a full pipe cannot deadlock the scan.
        let reader = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw PulseError.timeout }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            if process.isRunning { process.terminate() }
            try? await Task.sleep(for: .milliseconds(100))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = await reader.value
            pipe.fileHandleForReading.closeFile()
            throw error
        }
        let data = await reader.value
        pipe.fileHandleForReading.closeFile()
        try Task.checkCancellation()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
}

enum PulseError: Error { case unavailable, timeout }
