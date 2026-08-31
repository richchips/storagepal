import Foundation

enum PulseState: String, Sendable {
    case clear = "Looking good"
    case review = "Worth a look"
    case manual = "Manual check"
    case unavailable = "Not verified"

    var symbol: String {
        switch self {
        case .clear: "checkmark.circle.fill"
        case .review: "circle.dotted.circle.fill"
        case .manual: "arrow.up.forward.circle"
        case .unavailable: "questionmark.circle"
        }
    }
}

enum PulseArea: String, CaseIterable, Identifiable, Sendable {
    case storage, cleanup, startup, activity, encryption, firewall, updates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .storage: "Storage headroom"
        case .cleanup: "Everyday clutter"
        case .startup: "Startup helpers"
        case .activity: "App activity"
        case .encryption: "Disk encryption"
        case .firewall: "Network protection"
        case .updates: "Software & device updates"
        }
    }
    var symbol: String {
        switch self {
        case .storage: "externaldrive"
        case .cleanup: "sparkles"
        case .startup: "power"
        case .activity: "waveform.path"
        case .encryption: "lock.shield"
        case .firewall: "network.badge.shield.half.filled"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
    var actionLabel: String {
        switch self {
        case .storage: "Review storage"
        case .cleanup: "Review files"
        case .startup: "Review startup"
        case .activity: "Review activity"
        case .encryption, .firewall: "Open settings"
        case .updates: "Review updates"
        }
    }
}

struct PulseCheck: Identifiable, Sendable {
    let area: PulseArea
    let state: PulseState
    let detail: String
    let metric: String
    var id: PulseArea { area }
}

struct PulseReport: Sendable {
    let createdAt: Date
    let checks: [PulseCheck]
    var reviewCount: Int { checks.filter { $0.state == .review }.count }
    var verifiedCount: Int { checks.filter { $0.state == .clear || $0.state == .review }.count }
    var unverifiedCount: Int { checks.count - verifiedCount }
    var headline: String {
        if reviewCount > 0 { return "A little attention goes a long way." }
        return unverifiedCount > 0 ? "A few checks still need you." : "Everything checked looks good."
    }
}

struct PulseAppIdentity: Sendable {
    let pid: Int32
    let name: String
    let bundleURL: URL
    let launchDate: Date?
    let isBackground: Bool
}

struct PulseAppActivity: Identifiable, Sendable {
    let app: PulseAppIdentity
    let cpuPercent: Double
    let residentBytes: Int64
    var id: Int32 { app.pid }
    // Review thresholds, not evidence that an app is faulty or unnecessary.
    var warrantsReview: Bool { cpuPercent >= 20 || residentBytes >= 1_000_000_000 }
}

struct PulseCacheScan: Sendable {
    let candidates: [FileCandidate]
    let limitations: [String]
    var bytes: Int64 { candidates.reduce(0) { $0 + $1.bytes } }
}
