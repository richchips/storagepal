import AppKit
import Foundation

actor LocalArchivalHubService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    /// Calculates local storage footprint and estimated subscription cost for cloud storage services.
    func scanCloudSubscriptions() -> [CloudSubscriptionEstimate] {
        var results: [CloudSubscriptionEstimate] = []

        let cloudServices: [(type: CloudServiceType, possiblePaths: [String])] = [
            (
                .iCloud,
                [
                    "Library/Mobile Documents/com~apple~CloudDocs"
                ]
            ),
            (
                .dropbox,
                [
                    "Dropbox",
                    "Library/CloudStorage/Dropbox"
                ]
            ),
            (
                .googleDrive,
                [
                    "Google Drive",
                    "Library/CloudStorage/GoogleDrive"
                ]
            ),
            (
                .oneDrive,
                [
                    "OneDrive",
                    "Library/CloudStorage/OneDrive"
                ]
            )
        ]

        for (service, paths) in cloudServices {
            var detectedURL: URL?
            var usedBytes: Int64 = 0

            for relPath in paths {
                let url = home.appendingPathComponent(relPath)
                if fm.fileExists(atPath: url.path) {
                    detectedURL = url
                    usedBytes = measureDirectory(url)
                    break
                }
            }

            let isDetected = detectedURL != nil && usedBytes > 10_000_000 // ≥ 10 MB
            let (monthlyCost, yearlyCost) = estimateSubscriptionCost(for: service, bytes: usedBytes)

            results.append(
                CloudSubscriptionEstimate(
                    service: service,
                    localPath: detectedURL ?? home.appendingPathComponent(paths.first!),
                    isDetected: isDetected,
                    usedBytes: usedBytes,
                    estimatedMonthlyCostUSD: monthlyCost,
                    estimatedYearlyCostUSD: yearlyCost
                )
            )
        }

        return results
    }

    /// Discovers connected external backup drives and mounted network NAS shares.
    func scanNetworkAndExternalShares() -> [NetworkShareTarget] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey
        ]

        let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var targets: [NetworkShareTarget] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsInternal != true else { continue }

            let name = values.volumeName ?? url.lastPathComponent
            let total = values.volumeTotalCapacity.map { Int64($0) }
            let available = values.volumeAvailableCapacity.map { Int64($0) }

            targets.append(
                NetworkShareTarget(
                    name: name,
                    url: url,
                    isMounted: true,
                    totalBytes: total,
                    availableBytes: available
                )
            )
        }

        return targets
    }

    /// Connects to a local network share via smb:// or nfs://.
    @MainActor
    func connectToNetworkShare(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return NSWorkspace.shared.open(url)
    }

    // MARK: - Cost Estimation

    private func estimateSubscriptionCost(for service: CloudServiceType, bytes: Int64) -> (monthly: Double, yearly: Double) {
        guard bytes > 0 else { return (0, 0) }
        let gigabytes = Double(bytes) / 1_000_000_000.0

        switch service {
        case .iCloud:
            if gigabytes <= 50 { return (0.99, 11.88) }
            if gigabytes <= 200 { return (2.99, 35.88) }
            if gigabytes <= 2000 { return (9.99, 119.88) }
            return (29.99, 359.88)
        case .dropbox:
            return (11.99, 143.88)
        case .googleDrive:
            if gigabytes <= 100 { return (1.99, 23.88) }
            if gigabytes <= 200 { return (2.99, 35.88) }
            return (9.99, 119.88)
        case .oneDrive:
            if gigabytes <= 100 { return (1.99, 23.88) }
            return (6.99, 83.88)
        }
    }

    private func measureDirectory(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
