import Foundation

@MainActor
final class StorageSentinelService: ObservableObject {
    static let shared = StorageSentinelService()

    @Published private(set) var currentForecast: StorageForecast?
    @Published private(set) var runawaySpikeWarning: String?

    private let defaults = UserDefaults.standard
    private let snapshotsKey = "StoragePalVelocitySnapshots"
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {
        recordSnapshot()
        self.currentForecast = calculateForecast()
    }

    /// Records current disk capacity snapshot for velocity forecasting.
    func recordSnapshot() {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return
        }

        var history = loadSnapshots()
        let now = Date()

        // Only append if last record was > 6 hours ago
        if let last = history.last, now.timeIntervalSince(last.timestamp) < 6 * 3600 {
            return
        }

        let snapshot = StorageVelocitySnapshot(
            timestamp: now,
            availableBytes: Int64(available),
            totalBytes: Int64(total)
        )
        history.append(snapshot)

        // Keep last 60 data points (~15-30 days)
        if history.count > 60 {
            history = Array(history.suffix(60))
        }

        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: snapshotsKey)
        }
    }

    /// Calculates growth velocity, burn rate, and days until full.
    func calculateForecast() -> StorageForecast {
        let history = loadSnapshots()
        let checkSpike = detectRunawaySpikes()

        guard history.count >= 2,
              let first = history.first,
              let last = history.last else {
            return StorageForecast(
                dailyBurnRateBytes: 0,
                estimatedDaysRemaining: nil,
                velocityStatus: "Gathering baseline data",
                runawayFolderSpike: checkSpike
            )
        }

        let timeIntervalDays = max(1.0, last.timestamp.timeIntervalSince(first.timestamp) / 86400.0)
        let spaceDelta = first.availableBytes - last.availableBytes // Positive if available space shrank
        let dailyBurnRate = Int64(Double(spaceDelta) / timeIntervalDays)

        var daysRemaining: Int? = nil
        var status = "Storage footprint is stable"

        if dailyBurnRate > 500_000_000 { // Consuming > 500 MB/day
            daysRemaining = max(1, Int(last.availableBytes / dailyBurnRate))
            status = "Consuming ~\(ByteText.string(dailyBurnRate))/day"
        } else if dailyBurnRate < -100_000_000 { // Freeing > 100 MB/day
            status = "Reclaiming ~\(ByteText.string(abs(dailyBurnRate)))/day"
        }

        return StorageForecast(
            dailyBurnRateBytes: dailyBurnRate,
            estimatedDaysRemaining: daysRemaining,
            velocityStatus: status,
            runawayFolderSpike: checkSpike
        )
    }

    // MARK: - Runaway Leak Detection

    private func detectRunawaySpikes() -> String? {
        let logDir = home.appendingPathComponent("Library/Logs")
        let cacheDir = home.appendingPathComponent("Library/Caches")

        let logSize = measureDirectory(logDir)
        if logSize > 5_000_000_000 { // > 5 GB logs
            return "Application logs in ~/Library/Logs exceed \(ByteText.string(logSize)). Possible runaway logging daemon."
        }

        let cacheSize = measureDirectory(cacheDir)
        if cacheSize > 25_000_000_000 { // > 25 GB caches
            return "App caches in ~/Library/Caches exceed \(ByteText.string(cacheSize))."
        }

        return nil
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

    private func loadSnapshots() -> [StorageVelocitySnapshot] {
        guard let data = defaults.data(forKey: snapshotsKey),
              let decoded = try? JSONDecoder().decode([StorageVelocitySnapshot].self, from: data) else {
            return []
        }
        return decoded
    }
}
