import Foundation

enum UserCleanupAction: String, Codable {
    case trash
    case archive
    case keep
    case dismiss
}

struct FeatureWeights: Codable, Hashable {
    var pathWeights: [String: Double]
    var extensionWeights: [String: Double]
    var ageWeights: [String: Double]
    var sizeWeights: [String: Double]

    static var defaultWeights: FeatureWeights {
        FeatureWeights(
            pathWeights: [
                "Caches": 0.90,
                "DerivedData": 0.92,
                "Downloads": 0.75,
                "node_modules": 0.88,
                "Trash": 0.95,
                "Desktop": 0.50,
                "Documents": 0.35,
                "Movies": 0.60
            ],
            extensionWeights: [
                "tmp": 0.95,
                "log": 0.90,
                "dmg": 0.85,
                "pkg": 0.85,
                "iso": 0.85,
                "zip": 0.65,
                "mov": 0.60,
                "mp4": 0.55
            ],
            ageWeights: [
                "fresh": 0.25,     // < 14 days
                "moderate": 0.55,  // 14-60 days
                "stale": 0.85      // > 60 days
            ],
            sizeWeights: [
                "small": 0.35,     // < 50 MB
                "medium": 0.65,    // 50 MB - 500 MB
                "large": 0.88      // > 500 MB
            ]
        )
    }
}

struct StoragePreferenceModel: Codable {
    var totalActionsRecorded: Int
    var weights: FeatureWeights
    var lastUpdated: Date

    static var defaultModel: StoragePreferenceModel {
        StoragePreferenceModel(
            totalActionsRecorded: 0,
            weights: .defaultWeights,
            lastUpdated: Date()
        )
    }
}

@MainActor
final class StorageIntelligenceEngine: ObservableObject {
    @Published private(set) var model: StoragePreferenceModel
    private let defaults = UserDefaults.standard
    private let defaultsKey = "storagePreferenceModel"

    init() {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(StoragePreferenceModel.self, from: data) {
            self.model = decoded
        } else {
            self.model = .defaultModel
        }
    }

    func confidenceScore(for candidate: FileCandidate) -> Double {
        let pathScore = scoreForPath(candidate.url.path)
        let extScore = scoreForExtension(candidate.url.pathExtension.lowercased())
        let ageScore = scoreForAge(candidate.modifiedAt)
        let sizeScore = scoreForSize(candidate.bytes)

        let weightedScore = (pathScore * 0.35) + (extScore * 0.25) + (ageScore * 0.20) + (sizeScore * 0.20)
        return min(max(weightedScore, 0.05), 0.99)
    }

    func confidenceScore(for recommendation: StorageRecommendation) -> Double {
        guard !recommendation.candidates.isEmpty else { return 0.5 }
        let scores = recommendation.candidates.map { confidenceScore(for: $0) }
        let average = scores.reduce(0.0, +) / Double(scores.count)

        switch recommendation.kind {
        case .oldDownloads: return min(average * 1.1, 0.99)
        case .largeFiles: return min(average * 1.0, 0.99)
        case .archive: return min(average * 0.9, 0.99)
        case .developerCaches: return min(average * 1.2, 0.99)
        case .creativeCaches: return min(average * 1.15, 0.99)
        case .staleProjectArtifacts: return min(average * 1.1, 0.99)
        case .orphanedInstallers: return min(average * 1.25, 0.99)
        case .browserCaches: return min(average * 1.2, 0.99)
        case .staleSystemLogs: return min(average * 1.15, 0.99)
        case .trash, .desktop, .iCloud: return min(average, 0.99)
        }
    }

    func recordUserAction(_ action: UserCleanupAction, for candidate: FileCandidate) {
        let delta = (action == .trash || action == .archive) ? 0.05 : -0.05
        let pathKey = detectPathCategory(candidate.url.path)
        let extKey = candidate.url.pathExtension.lowercased()
        let ageKey = ageCategory(for: candidate.modifiedAt)
        let sizeKey = sizeCategory(for: candidate.bytes)

        if let current = model.weights.pathWeights[pathKey] {
            model.weights.pathWeights[pathKey] = min(max(current + delta, 0.05), 0.99)
        }
        if !extKey.isEmpty, let current = model.weights.extensionWeights[extKey] {
            model.weights.extensionWeights[extKey] = min(max(current + delta, 0.05), 0.99)
        } else if !extKey.isEmpty {
            model.weights.extensionWeights[extKey] = min(max(0.5 + delta, 0.05), 0.99)
        }

        if let current = model.weights.ageWeights[ageKey] {
            model.weights.ageWeights[ageKey] = min(max(current + delta, 0.05), 0.99)
        }
        if let current = model.weights.sizeWeights[sizeKey] {
            model.weights.sizeWeights[sizeKey] = min(max(current + delta, 0.05), 0.99)
        }

        model.totalActionsRecorded += 1
        model.lastUpdated = Date()
        saveModel()
    }

    private func saveModel() {
        if let encoded = try? JSONEncoder().encode(model) {
            defaults.set(encoded, forKey: defaultsKey)
        }
    }

    private func scoreForPath(_ path: String) -> Double {
        let category = detectPathCategory(path)
        return model.weights.pathWeights[category] ?? 0.50
    }

    private func scoreForExtension(_ ext: String) -> Double {
        guard !ext.isEmpty else { return 0.50 }
        return model.weights.extensionWeights[ext] ?? 0.50
    }

    private func scoreForAge(_ date: Date?) -> Double {
        let category = ageCategory(for: date)
        return model.weights.ageWeights[category] ?? 0.50
    }

    private func scoreForSize(_ bytes: Int64) -> Double {
        let category = sizeCategory(for: bytes)
        return model.weights.sizeWeights[category] ?? 0.50
    }

    private func detectPathCategory(_ path: String) -> String {
        if path.contains("Caches") { return "Caches" }
        if path.contains("DerivedData") { return "DerivedData" }
        if path.contains("node_modules") { return "node_modules" }
        if path.contains("Downloads") { return "Downloads" }
        if path.contains("Trash") || path.contains(".Trash") { return "Trash" }
        if path.contains("Desktop") { return "Desktop" }
        if path.contains("Movies") { return "Movies" }
        if path.contains("Documents") { return "Documents" }
        return "General"
    }

    private func ageCategory(for date: Date?) -> String {
        guard let date else { return "moderate" }
        let days = Date().timeIntervalSince(date) / (24 * 3600)
        if days < 14 { return "fresh" }
        if days < 60 { return "moderate" }
        return "stale"
    }

    private func sizeCategory(for bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb < 50 { return "small" }
        if mb < 500 { return "medium" }
        return "large"
    }
}
