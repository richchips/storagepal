import Foundation
import SwiftUI

enum StorageHealth: String, Codable {
    case calm
    case watch
    case urgent

    var title: String {
        switch self {
        case .calm: "Looking good"
        case .watch: "A little crowded"
        case .urgent: "Time to make room"
        }
    }

    var tint: Color {
        switch self {
        case .calm: Color(red: 0.22, green: 0.63, blue: 0.48)
        case .watch: Color(red: 0.91, green: 0.58, blue: 0.18)
        case .urgent: Color(red: 0.86, green: 0.28, blue: 0.26)
        }
    }
}

struct DiskSnapshot: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let totalBytes: Int64
    let availableBytes: Int64
    let isInternal: Bool
    let isRemovable: Bool

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

struct FolderSnapshot: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let bytes: Int64
    let fileCount: Int
    let kind: FolderKind
}

enum FolderKind: String, Hashable {
    case desktop
    case downloads
    case documents
    case movies
    case pictures
    case music
    case trash
    case caches
    case iCloud

    var symbol: String {
        switch self {
        case .desktop: "macwindow"
        case .downloads: "arrow.down.circle"
        case .documents: "doc.on.doc"
        case .movies: "film"
        case .pictures: "photo.on.rectangle"
        case .music: "music.note"
        case .trash: "trash"
        case .caches: "shippingbox"
        case .iCloud: "icloud"
        }
    }
}

struct FileCandidate: Identifiable, Hashable {
    let id: String
    let url: URL
    let bytes: Int64
    let modifiedAt: Date?
    let isCloudItem: Bool
    var confidenceScore: Double = 0.50

    var name: String { url.lastPathComponent }
}

enum RecommendationKind: String, Hashable {
    case trash
    case oldDownloads
    case largeFiles
    case desktop
    case iCloud
    case archive
    case developerCaches
    case creativeCaches
    case staleProjectArtifacts
    case orphanedInstallers
    case browserCaches
    case staleSystemLogs

    var symbol: String {
        switch self {
        case .trash: "trash"
        case .oldDownloads: "clock.arrow.circlepath"
        case .largeFiles: "arrow.up.left.and.arrow.down.right"
        case .desktop: "sparkles.rectangle.stack"
        case .iCloud: "icloud.and.arrow.down"
        case .archive: "externaldrive"
        case .developerCaches: "hammer"
        case .creativeCaches: "paintpalette"
        case .staleProjectArtifacts: "folder.badge.gearshape"
        case .orphanedInstallers: "shippingbox"
        case .browserCaches: "globe"
        case .staleSystemLogs: "doc.text.magnifyingglass"
        }
    }
}

struct StorageRecommendation: Identifiable, Hashable {
    let id: String
    let kind: RecommendationKind
    let title: String
    let detail: String
    let reclaimableBytes: Int64
    let candidates: [FileCandidate]
    let actionLabel: String
    var confidenceScore: Double = 0.50

    var confidencePercentageText: String {
        "\(Int(confidenceScore * 100))% match"
    }
}

struct ScanReport {
    let createdAt: Date
    let disks: [DiskSnapshot]
    let folders: [FolderSnapshot]
    let largestFiles: [FileCandidate]
    let recommendations: [StorageRecommendation]
    let skippedLocations: [URL]

    var internalDisk: DiskSnapshot? { disks.first(where: { $0.isInternal }) ?? disks.first }
    var externalDisks: [DiskSnapshot] { disks.filter { !$0.isInternal } }
    var iCloudFolder: FolderSnapshot? { folders.first(where: { $0.kind == .iCloud }) }
    var potentialSavings: Int64 {
        var seenFiles = Set<String>()
        var total: Int64 = 0
        for recommendation in recommendations {
            if recommendation.candidates.isEmpty {
                total += recommendation.reclaimableBytes
                continue
            }
            for candidate in recommendation.candidates where seenFiles.insert(candidate.id).inserted {
                total += candidate.bytes
            }
        }
        return total
    }

    var health: StorageHealth {
        guard let disk = internalDisk, disk.totalBytes > 0 else { return .watch }
        let freeFraction = Double(disk.availableBytes) / Double(disk.totalBytes)
        if freeFraction < 0.08 || disk.availableBytes < 10_000_000_000 { return .urgent }
        if freeFraction < 0.18 || disk.availableBytes < 25_000_000_000 { return .watch }
        return .calm
    }
}

enum ScanFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case manual

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var interval: TimeInterval {
        switch self {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        case .manual: .infinity
        }
    }
}

enum ByteText {
    static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}

enum MaintenanceAction: String, Codable, CaseIterable, Identifiable {
    case archiveToFolder = "archive"
    case moveToTrash = "trash"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .archiveToFolder: "Archive to folder / drive"
        case .moveToTrash: "Move to Trash"
        }
    }
}

enum MaintenanceSchedule: String, Codable, CaseIterable, Identifiable {
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case manual = "manual"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var interval: TimeInterval {
        switch self {
        case .hourly: 60 * 60
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        case .monthly: 30 * 24 * 60 * 60
        case .manual: .infinity
        }
    }
}

struct MaintenanceRule: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var isEnabled: Bool
    var sourceFolderURL: URL
    var targetAction: MaintenanceAction
    var destinationFolderURL: URL?
    var schedule: MaintenanceSchedule
    var minAgeDays: Int
    var minFileBytes: Int64
    var notifyOnExecution: Bool
    var lastRunDate: Date?

    var sourceFolderName: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return sourceFolderURL.path.replacingOccurrences(of: home, with: "~")
    }
}

struct LowSpaceTriggerConfig: Codable, Hashable {
    var isEnabled: Bool
    var thresholdGB: Double
    var autoExecuteRules: Bool
    var lastTriggeredDate: Date?

    static var defaultConfig: LowSpaceTriggerConfig {
        LowSpaceTriggerConfig(isEnabled: true, thresholdGB: 25.0, autoExecuteRules: false, lastTriggeredDate: nil)
    }
}

struct MaintenanceLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: Date
    let ruleName: String
    let actionDescription: String
    let filesProcessedCount: Int
    let reclaimedBytes: Int64
    let wasTriggeredByLowSpace: Bool
    let errorDetails: String?
}

struct InstalledAppLeftover: Identifiable, Hashable {
    var id: String { url.path }
    let category: String
    let url: URL
    let bytes: Int64
}

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let appURL: URL
    let appSizeBytes: Int64
    let leftovers: [InstalledAppLeftover]

    var leftoverSizeBytes: Int64 {
        leftovers.reduce(0) { $0 + $1.bytes }
    }

    var totalReclaimableBytes: Int64 {
        appSizeBytes + leftoverSizeBytes
    }
}

// MARK: - CCleaner Pro Expansion Models

struct OrphanedAppResidue: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let name: String
    let bundleIdentifier: String?
    let category: String
    let url: URL
    let bytes: Int64
    let lastModified: Date?
}

enum StartupItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case userLaunchAgent = "User Launch Agent"
    case systemLaunchAgent = "System Launch Agent"
    case loginItem = "Login Item"
    case orphanedAgent = "Orphaned Agent"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .userLaunchAgent: "person.badge.shield.checkmark"
        case .systemLaunchAgent: "gearshape.2"
        case .loginItem: "arrow.right.circle"
        case .orphanedAgent: "exclamationmark.triangle.fill"
        }
    }
}

struct StartupItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let label: String
    let kind: StartupItemKind
    let plistURL: URL?
    let targetExecutablePath: String?
    let isExecutableMissing: Bool
    var isEnabled: Bool
    let runAtLoad: Bool
}

enum BrowserType: String, CaseIterable, Identifiable, Sendable {
    case safari = "Safari"
    case chrome = "Google Chrome"
    case brave = "Brave Browser"
    case firefox = "Firefox"
    case edge = "Microsoft Edge"
    case opera = "Opera"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .safari: "safari"
        case .chrome: "globe"
        case .brave: "shield.checkerboard"
        case .firefox: "flame"
        case .edge: "e.circle"
        case .opera: "o.circle"
        }
    }
}

struct BrowserCacheGroup: Identifiable, Hashable, Sendable {
    var id: String { cacheURL.path }
    let browser: BrowserType
    let cacheURL: URL
    let bytes: Int64
    let fileCount: Int
    let detail: String
}

struct SystemLogGroup: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let name: String
    let category: String
    let url: URL
    let bytes: Int64
    let fileCount: Int
    let oldestFileDate: Date?
}

enum PhotoQualityKind: String, CaseIterable, Identifiable, Sendable {
    case screenshot = "Screenshots"
    case blurryOrDark = "Blurry & Low Exposure"
    case duplicates = "Twins & Duplicates"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .screenshot: "macwindow.on.rectangle"
        case .blurryOrDark: "camera.metering.unknown"
        case .duplicates: "photo.stack"
        }
    }
}

struct PhotoQualityItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bytes: Int64
    let kind: PhotoQualityKind
    let reason: String
    let createdAt: Date?
}

// MARK: - Next-Gen Innovation Models

// 1. Pal Vault Models
struct VaultEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let originalSize: Int64
    let encryptedSize: Int64
    let addedDate: Date
    let fileExtension: String
    let relativeStoragePath: String
}

enum VaultLockState: String, Sendable {
    case locked
    case unlocked
    case authenticating
}

// 2. Confidential Sanitizer Models
struct SanitizerMetadataReport: Hashable, Sendable {
    let hasGPS: Bool
    let gpsCoordinates: String?
    let cameraModel: String?
    let author: String?
    let software: String?
    let creationDate: Date?
    let tagsCount: Int
}

struct SanitizerItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bytes: Int64
    let fileExtension: String
    let report: SanitizerMetadataReport
}

// 3. Storage Forecaster & Sentinel Models
struct StorageVelocitySnapshot: Codable, Hashable, Sendable {
    let timestamp: Date
    let availableBytes: Int64
    let totalBytes: Int64
}

struct StorageForecast: Hashable, Sendable {
    let dailyBurnRateBytes: Int64 // Positive = consuming storage, Negative = freeing space
    let estimatedDaysRemaining: Int?
    let velocityStatus: String
    let runawayFolderSpike: String?
}

// 4. Universal Drive Consolidator Models
struct VolumeFileEntry: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let volumeName: String
    let url: URL
    let size: Int64
    let modifiedDate: Date?
}

struct CrossVolumeDuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let hash: String
    let fileName: String
    let size: Int64
    let entries: [VolumeFileEntry]

    var wastedBytes: Int64 {
        guard entries.count > 1 else { return 0 }
        return size * Int64(entries.count - 1)
    }
}

struct DriveConsolidationPlan: Hashable, Sendable {
    let sourceVolumes: [String]
    let targetDirectory: URL
    let totalFilesToConsolidate: Int
    let totalBytesToCopy: Int64
    let redundantDuplicateBytesSaved: Int64
}

// 5. "Own Your Data" Local Archival Hub Models
enum CloudServiceType: String, CaseIterable, Identifiable, Sendable {
    case iCloud = "iCloud Drive"
    case dropbox = "Dropbox"
    case googleDrive = "Google Drive"
    case oneDrive = "OneDrive"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .iCloud: "icloud.fill"
        case .dropbox: "shippingbox.fill"
        case .googleDrive: "externaldrive.badge.icloud"
        case .oneDrive: "cloud.fill"
        }
    }
}

struct CloudSubscriptionEstimate: Identifiable, Hashable, Sendable {
    var id: String { service.rawValue }
    let service: CloudServiceType
    let localPath: URL
    let isDetected: Bool
    let usedBytes: Int64
    let estimatedMonthlyCostUSD: Double
    let estimatedYearlyCostUSD: Double
}

struct NetworkShareTarget: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    let name: String
    let url: URL
    let isMounted: Bool
    let totalBytes: Int64?
    let availableBytes: Int64?
}

// MARK: - Redaction & AI Token Swap Models

enum PrivacyPolicyTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case internalClinical = "Internal Clinical (Standard)"
    case externalResearch = "External Research / Public (Strict)"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .internalClinical:
            return "Replaces direct identifiers (names, patient IDs, addresses, contact details) with tokens while preserving clinical meaning, dates, and dosages."
        case .externalResearch:
            return "Strict de-identification: tokenizes direct identifiers plus quasi-identifiers (exact dates, exact ages, specific localities)."
        }
    }
}

enum SensitiveEntityTier: String, Codable, Sendable {
    case directIdentifier = "Direct Identifier (Tier 1)"
    case quasiIdentifier = "Quasi-Identifier (Tier 2)"
}

enum RedactionTemplateKind: String, CaseIterable, Identifiable, Sendable {
    case clinicalPsychology = "Clinical Notes & Psychology"
    case medical = "Medical & Health"
    case financial = "Financial & Tax"
    case legal = "Legal & Contracts"
    case hr = "HR & Resumes"
    case custom = "Custom Keyword & Regex"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .clinicalPsychology: "brain.head.profile"
        case .medical: "cross.case"
        case .financial: "banknote"
        case .legal: "scale.3d"
        case .hr: "person.crop.rectangle.badge.plus"
        case .custom: "slider.horizontal.3"
        }
    }

    var defaultDescription: String {
        switch self {
        case .clinicalPsychology: "Detects Client Names, Patient/NHS/MRN IDs, Addresses, and Contact Info while strictly preserving clinical formulation, symptoms, and medication doses."
        case .medical: "Detects & masks Patient Names, Dates of Birth, MRN/NHS Numbers, Addresses, and Provider details."
        case .financial: "Detects & masks SSN, Tax IDs, Bank Accounts, IBANs, Credit Cards, and Salary figures."
        case .legal: "Detects & masks Client Names, Settlement Amounts, Signatures, and Internal Case Numbers."
        case .hr: "Detects & masks Home Addresses, Personal Phones, Personal Emails, Age, and Past Salaries."
        case .custom: "Redacts user-specified custom keywords, codenames, and regular expression patterns."
        }
    }
}

enum RedactionMode: String, CaseIterable, Identifiable, Sendable {
    case aiTokenSwap = "AI Token Swap (Reversible)"
    case blackout = "Permanent Blackout"
    case redactedLabel = "[REDACTED] Text Label"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .aiTokenSwap: "sparkles"
        case .blackout: "square.fill"
        case .redactedLabel: "tag.fill"
        }
    }
}

struct SensitiveEntityMatch: Identifiable, Hashable, Sendable {
    let id: String
    let category: String
    let originalText: String
    let tokenReplacement: String
    let pageIndex: Int
    var isEnabled: Bool
    var tier: SensitiveEntityTier

    init(
        id: String = UUID().uuidString,
        category: String,
        originalText: String,
        tokenReplacement: String,
        pageIndex: Int = 1,
        isEnabled: Bool = true,
        tier: SensitiveEntityTier = .directIdentifier
    ) {
        self.id = id
        self.category = category
        self.originalText = originalText
        self.tokenReplacement = tokenReplacement
        self.pageIndex = pageIndex
        self.isEnabled = isEnabled
        self.tier = tier
    }
}

struct TokenSwapSession: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let documentName: String
    let template: String
    let createdAt: Date
    let tokenMap: [String: String] // e.g. "[PERSON_1]": "John Doe"
    let realToTokenMap: [String: String] // e.g. "John Doe": "[PERSON_1]"
}

// MARK: - Clipboard Guard & Prompt Presets

enum ClipboardSensitiveKind: String, Sendable {
    case openAIKey = "OpenAI API Key"
    case anthropicKey = "Anthropic API Key"
    case awsKey = "AWS Access Key"
    case githubToken = "GitHub Token"
    case privateKey = "Private Encryption Key"
    case creditCard = "Credit Card Number"
    case ssn = "Social Security Number"

    var symbol: String {
        switch self {
        case .openAIKey, .anthropicKey, .awsKey, .githubToken: "key.fill"
        case .privateKey: "lock.shield.fill"
        case .creditCard: "creditcard.fill"
        case .ssn: "person.text.rectangle.fill"
        }
    }
}

struct ClipboardSensitiveItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: ClipboardSensitiveKind
    let snippet: String
    let rawText: String
}

enum AIPromptRolePreset: String, CaseIterable, Identifiable, Sendable {
    case general = "General AI Assistant"
    case legal = "Legal Contract Counsel"
    case financial = "Financial & Tax CPA"
    case medical = "Clinical Medical Assistant"
    case hrResume = "HR & Talent Recruiter"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "sparkles"
        case .legal: "scale.3d"
        case .financial: "chart.pie.fill"
        case .medical: "cross.case.fill"
        case .hrResume: "person.text.rectangle"
        }
    }

    var systemPreamble: String {
        switch self {
        case .general:
            return "You are an AI assistant. Analyze the following sanitized document. IMPORTANT: All sensitive entities have been pseudonymized with placeholder tokens like [PERSON_1] or [AMOUNT_1]. You must strictly retain and preserve all bracketed placeholder tokens verbatim in your response so real data can be restored."
        case .legal:
            return "You are an expert legal contract counsel. Review this agreement, analyze obligations, identify risks, and suggest improvements. CRITICAL: All client names, parties, and case references are pseudonymized with tokens like [PARTY_1], [CASE_ID_1], and [SETTLEMENT_1]. Strictly preserve all bracketed tokens verbatim throughout your analysis."
        case .financial:
            return "You are a senior financial analyst and CPA. Analyze the following financial statement/tax document for income breakdowns, tax liabilities, and anomalies. CRITICAL: Account numbers and dollar figures are replaced with tokens like [AMOUNT_1], [SSN_1], and [BANK_ACCOUNT_1]. Maintain all bracketed tokens verbatim in your response."
        case .medical:
            return "You are a clinical documentation assistant. Summarize patient history, symptoms, and treatment plans clearly. CRITICAL: Patient identifiers and doses are pseudonymized with [PATIENT_ID_1], [DOB_1], and [DOSAGE_1]. Retain all bracketed tokens verbatim in your response."
        case .hrResume:
            return "You are an executive talent recruiter and career coach. Review and rewrite this resume for clarity, executive impact, and measurable achievements. CRITICAL: Personal names and contact details are pseudonymized with [PERSON_1], [PHONE_1], and [EMAIL_1]. Preserve all bracketed tokens verbatim."
        }
    }
}

struct ManualRedactionBox: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let rectNormalized: [Double] // [x, y, width, height] normalized (0.0 to 1.0)
    let pageIndex: Int
}

// MARK: - In-App Software Update Models

struct AppReleaseInfo: Codable, Identifiable, Equatable, Sendable {
    var id: String { version }
    let version: String
    let releaseDate: String
    let releaseNotes: String
    let downloadURL: String
    let sha256: String?
    let minimumMacOSVersion: String?
}

enum UpdateCheckStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(AppReleaseInfo)
    case downloading(progress: Double)
    case readyToRelaunch(stagedURL: URL)
    case failed(String)

    var isCheckingOrDownloading: Bool {
        switch self {
        case .checking, .downloading: return true
        default: return false
        }
    }
}




