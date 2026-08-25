# AGENTS.md

Welcome to **Storage Pal**, a native macOS utility built with Swift and SwiftUI for managing local and iCloud storage with a calm, review-first approach.

This document serves as a comprehensive guide for AI agents and developers working on this codebase.

---

## 1. Project Overview & Mission

Storage Pal is designed for Mac users who repeatedly run out of disk space. It lives in the macOS menu bar and provides a dedicated dashboard window.

### Key Philosophy & Principles
- **Review-First & Safe**: Storage Pal never deletes files automatically. File actions (moving to Trash or archiving) require explicit user confirmation.
- **Non-Destructive**: Deletions use `FileManager.default.trashItem(at:resultingItemURL:)` so items remain in macOS Trash and are recoverable until the user empties Trash.
- **Calm UI**: Designed with modern SwiftUI components, custom color palettes (Cream, Mint, Ink, Mist), clear typography, and gentle recommendations instead of alarming prompts.
- **iCloud Transparency**: Respects Apple's sandbox boundaries. Measures accessible local iCloud Drive storage and links directly to system settings for authoritative iCloud account management.

---

## 2. Technical Stack & Requirements

- **Language**: Swift 5.9+
- **Frameworks**: SwiftUI, AppKit, ServiceManagement (`SMAppService`), UserNotifications (`UNUserNotificationCenter`)
- **Platform Target**: macOS 14.0 (Sonoma) or newer
- **Build System**: Swift Package Manager (`Package.swift`)
- **Distribution**: Packaged `.app` bundle archived in `dist/Storage Pal.zip`

---

## 3. Repository Architecture & Directory Structure

```
Storage Pal/
├── AppResources/
│   └── Info.plist               # App bundle metadata (com.storagepal.mac, v0.1.0)
├── Package.swift                # SPM package definition targeting macOS 14 executable
├── README.md                    # User-facing documentation & build instructions
├── AGENTS.md                    # Developer and AI agent guidelines (this file)
├── CHANGELOG.md                 # Version release history
├── dist/                        # Output folder for compiled Storage Pal.zip
├── scripts/
│   └── package-app.sh           # Zsh script to build, bundle, sign, and zip app
└── Sources/
    └── StoragePal/              # Core executable target
        ├── StoragePalApp.swift  # @main entrypoint, WindowGroup, MenuBarExtra, Settings
        ├── Models/
        │   └── StorageModels.swift # Domain models (ScanReport, InstalledApp, MaintenanceRule, etc.)
        ├── Services/
        │   ├── AppModel.swift   # @MainActor view model coordinating scans, actions, triggers, and state
        │   ├── AppErrorLogService.swift # Diagnostic error logger and 1-click clipboard exporter
        │   ├── FileTrashService.swift # Multi-tiered safe trashing engine (Foundation, unlock/chmod, Finder AppleScript, Admin move)
        │   ├── FullDiskAccessService.swift # Proactive TCC/FDA status probe, observer, and Settings deep linker
        │   ├── OrphanedResidueService.swift # Scans ~/Library for ghost leftovers from previously uninstalled applications
        │   ├── StartupManagerService.swift # Inspects LaunchAgents and startup daemons; flags broken background helpers
        │   ├── BrowserCleanerService.swift # Scans and clears disposable browser web/media caches without touching cookies/logins
        │   ├── SystemLogCleanerService.swift # Scans and cleans stale crash dumps, .ips, and diagnostic logs older than 14 days
        │   ├── PhotoQualityService.swift # Detects screenshot clutter, low-resolution accidental thumbnails, and blurry shots
        │   ├── PalVaultService.swift # CryptoKit AES-GCM-256 encrypted vault with Keychain Touch ID biometrics & auto-lock
        │   ├── MetadataSanitizerService.swift # Strips hidden EXIF, GPS coordinates, camera serials, and PDF revision history
        │   ├── AIWatermarkSanitizerService.swift # Strips zero-width steganography, variation selectors, homoglyphs, and AI preambles
        │   ├── DocumentRedactionEngine.swift # Domain-specific regex/entity matching and true structural PDF redaction
        │   ├── AITokenSwapService.swift # AI Privacy Proxy: forward pseudonymization and reverse real-data restoration
        │   ├── AppUpdateService.swift # In-app software update checker, semver comparator, and staging/relaunch engine
        │   ├── ClipboardGuardService.swift # Proactive background clipboard monitor for API keys, passwords, and sensitive PII
        │   ├── SecureShredderService.swift # DoD 3-pass cryptographic random/zero file shredder with hardware flush
        │   ├── StorageSentinelService.swift # Storage velocity forecaster & runaway log/cache explosion watcher
        │   ├── DriveConsolidatorService.swift # Multi-volume cross-drive duplicate file detector and backup merger
        │   ├── LocalArchivalHubService.swift # Cloud subscription savings estimator, NAS SMB connection helper, and local migration
        │   ├── StorageScanner.swift # Swift actor for async filesystem enumeration
        │   ├── DeveloperScanner.swift # Scans Xcode, node_modules, .venv, Cargo, and creative caches
        │   ├── StorageIntelligenceEngine.swift # On-device machine learning preference scoring & reinforcement model
        │   ├── AppUninstallerService.swift # Scans /Applications and hunts hidden ~/Library leftover folders
        │   ├── DuplicateFinderService.swift # Multi-stage streaming SHA-256 universal duplicate file finder
        │   ├── ICloudEvictionService.swift # Scans downloaded local iCloud items and triggers evictUbiquitousItem
        │   ├── ICloudManagerService.swift # Scans and untangles iCloud folders, app containers, local/cloud split, and ghost apps
        │   ├── MediaCompressorService.swift # AVFoundation HEVC video transcoder and Quartz PDF compressor
        │   ├── PhotoDeduplicatorService.swift # Apple Vision perceptual feature print photo twin deduplicator
        │   └── TreemapLayout.swift # Proportional spatial treemap folder partitioning algorithm
        └── Views/
            ├── Components.swift # Design system (PalCard, StorageBar, PalButtonStyle, SectionHeading)
            ├── DashboardView.swift # Main window & sidebar layout (Today, Tidy, Duplicates, Apps, Startup, Photos, Vault, Sanitize, Consolidate, Own Your Data, Treemap, Drives, iCloud, Automate)
            ├── DetailViews.swift # Detail screens (TidyListView, DrivesView, ICloudView, FileReviewView, SettingsView)
            ├── DuplicateFinderView.swift # Universal duplicate file inspector, copy report helper, and batch cleaner
            ├── AutomationView.swift # Scheduled maintenance rules, low-disk capacity triggers, dry run preview, and audit history
            ├── AppUninstallerView.swift # Installed app search, orphaned leftovers inspector, and complete 1-click uninstaller sheet
            ├── StartupManagerView.swift # Startup items and LaunchAgents manager with enable/disable toggles and orphan detection
            ├── BrowserCleanerView.swift # Zero-risk browser cache reviewer and cleaner modal
            ├── PermissionRecoverySheet.swift # Interactive permission recovery modal for blocked files with FDA deep links
            ├── PhotoDeduplicatorView.swift # Visual photo twin detector, screenshot sweeper, and blur/low-quality gallery
            ├── PalVaultView.swift # Biometric Touch ID privacy vault and AES-GCM encrypted file explorer
            ├── ConfidentialSanitizerView.swift # EXIF/GPS metadata inspector, clean copier, document redaction studio, and shredder
            ├── AITokenRestoreSheet.swift # AI Privacy Bridge modal to reverse pseudonymized tokens and restore real confidential data
            ├── AppUpdateSheet.swift # In-app software updater modal with release notes, progress bar, and 1-click install
            ├── DriveConsolidatorView.swift # Cross-volume multi-drive duplicate comparator and merge planner
            ├── LocalArchivalHubView.swift # Cloud subscription cost calculator, local/external drive manager, and NAS helper
            └── TreemapView.swift # Interactive visual proportional treemap and inspector
```

### Source File Breakdown

| File | Primary Responsibility | Key Types / Abstractions |
| :--- | :--- | :--- |
| [`StoragePalApp.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/StoragePalApp.swift) | Main application lifecycle, WindowGroup configuration, MenuBarExtra status item, and Settings scene. | `StoragePalApp`, `MenuBarContent` |
| [`StorageModels.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Models/StorageModels.swift) | Data models representing storage health, volume snapshots, folder usage, file candidates, recommendations, installed apps, orphaned residue, startup items, browser caches, vault entries, sanitizer reports, redaction matches, token swap sessions, forecasts, cross-volume duplicates, and cloud subscription estimates. | `StorageHealth`, `DiskSnapshot`, `FileCandidate`, `StorageRecommendation`, `InstalledApp`, `OrphanedAppResidue`, `StartupItem`, `BrowserCacheGroup`, `SystemLogGroup`, `PhotoQualityItem`, `VaultEntry`, `SanitizerItem`, `RedactionTemplateKind`, `RedactionMode`, `SensitiveEntityMatch`, `TokenSwapSession`, `StorageForecast`, `CrossVolumeDuplicateGroup`, `CloudSubscriptionEstimate`, `NetworkShareTarget` |
| [`AppModel.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/AppModel.swift) | Central `@MainActor` observable object. Coordinates scanning tasks, scheduler, notifications, system deep-links, `trashItem` moves, archiving, and intelligence engine updates. | `AppModel` |
| [`AppErrorLogService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/AppErrorLogService.swift) | Centralized diagnostic error capture, stack trace logging, and 1-click clipboard copying. | `AppErrorLogService`, `DiagnosticLogEntry` |
| [`FileTrashService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/FileTrashService.swift) | Resilient safe trashing service utilizing Foundation trashing, ACL unlocking, Finder AppleScript, and admin elevation. | `FileTrashService`, `TrashOperationResult`, `BatchTrashSummary` |
| [`FullDiskAccessService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/FullDiskAccessService.swift) | TCC/FDA status probe, live focus change listener, and direct System Settings URL routing. | `FullDiskAccessService` |
| [`OrphanedResidueService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/OrphanedResidueService.swift) | Scans `~/Library` for ghost leftover directories from previously uninstalled software. | `OrphanedResidueService` |
| [`StartupManagerService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/StartupManagerService.swift) | Inspects `~/Library/LaunchAgents` and `/Library/LaunchAgents` for startup helpers, broken daemons, and enable/disable toggles. | `StartupManagerService` |
| [`BrowserCleanerService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/BrowserCleanerService.swift) | Safely scans and clears disposable HTTP caches across Safari, Chrome, Brave, Firefox, Edge without affecting logins. | `BrowserCleanerService` |
| [`SystemLogCleanerService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/SystemLogCleanerService.swift) | Sweeps crash reports, diagnostic dumps, and logs older than 14 days in `~/Library/Logs`. | `SystemLogCleanerService` |
| [`PhotoQualityService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/PhotoQualityService.swift) | Detects accumulated screenshots on Desktop/Downloads and blurry/low-resolution photo clutter. | `PhotoQualityService` |
| [`PalVaultService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/PalVaultService.swift) | CryptoKit AES-GCM-256 encrypted storage vault with Keychain Touch ID biometrics, sleep observation, and auto-lock. | `PalVaultService` |
| [`MetadataSanitizerService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/MetadataSanitizerService.swift) | Strips hidden EXIF, GPS geolocation, camera metadata, and PDF revision histories before file sharing. | `MetadataSanitizerService` |
| [`AIWatermarkSanitizerService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/AIWatermarkSanitizerService.swift) | Strips hidden zero-width spaces, variation selectors, homoglyphs, and AI conversational preambles from text & documents. | `AIWatermarkSanitizerService`, `AIWatermarkReport` |
| [`DocumentRedactionEngine.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/DocumentRedactionEngine.swift) | Domain template regex/entity matching and true structural PDF redaction renderer. | `DocumentRedactionEngine` |
| [`AITokenSwapService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/AITokenSwapService.swift) | AI Privacy Proxy: forward pseudonymization generator, encrypted local session vault, and reverse de-anonymizer. | `AITokenSwapService` |
| [`SecureShredderService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/SecureShredderService.swift) | Performs permanent 3-pass DoD cryptographic overwriting (random bytes $\rightarrow$ complement pattern $\rightarrow$ zero-fill $\rightarrow$ `F_FULLFSYNC`). | `SecureShredderService` |
| [`StorageSentinelService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/StorageSentinelService.swift) | Storage velocity forecaster predicting days until SSD saturation and detecting runaway log/cache size spikes. | `StorageSentinelService` |
| [`DriveConsolidatorService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/DriveConsolidatorService.swift) | Multi-volume streaming SHA-256 duplicate scanner and automated drive merge planner. | `DriveConsolidatorService` |
| [`LocalArchivalHubService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/LocalArchivalHubService.swift) | Cloud storage footprint and recurring subscription savings estimator ($/yr) + local SMB/NFS NAS connection assistant. | `LocalArchivalHubService` |
| [`StorageScanner.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/StorageScanner.swift) | Background Swift `actor` executing async directory traversals, capacity calculations, and recommendation construction. | `StorageScanner` |
| [`DeveloperScanner.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/DeveloperScanner.swift) | Background scanner for Xcode `DerivedData`/`Archives`, untouched `node_modules`, Cargo `target/`, `.venv`, and orphaned DMG/PKG installers. | `DeveloperScanner` |
| [`StorageIntelligenceEngine.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/StorageIntelligenceEngine.swift) | Privacy-first on-device weighted machine learning model computing confidence scores and tuning weights based on user cleanup actions. | `StorageIntelligenceEngine`, `StoragePreferenceModel` |
| [`AppUninstallerService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/AppUninstallerService.swift) | Scans `/Applications` and hunts associated hidden folders across `~/Library/Application Support`, `Containers`, `Preferences`, `Caches`, etc. | `AppUninstallerService` |
| [`DuplicateFinderService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/DuplicateFinderService.swift) | High-performance multi-stage file deduplicator using size filtering and streaming SHA-256 chunk hashing. | `DuplicateFinderService`, `DuplicateFileGroup` |
| [`ICloudEvictionService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/ICloudEvictionService.swift) | Identifies downloaded local iCloud items and calls `FileManager.evictUbiquitousItem` to free local SSD space. | `ICloudEvictionService` |
| [`MediaCompressorService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/MediaCompressorService.swift) | Hardware-accelerated `AVFoundation` HEVC video transcoder and Quartz `PDFDocument` compressor. | `MediaCompressorService` |
| [`PhotoDeduplicatorService.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/PhotoDeduplicatorService.swift) | Perceptual visual hash duplicate finder utilizing Apple's `Vision` framework (`VNGenerateImageFeaturePrintRequest`). | `PhotoDeduplicatorService`, `PhotoDuplicateGroup` |
| [`TreemapLayout.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Services/TreemapLayout.swift) | Proportional spatial layout builder for rendering squarified treemaps of nested folder trees. | `TreemapNode`, `TreemapBuilder` |
| [`DashboardView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/DashboardView.swift) | Main window layout with multi-tab sidebar (Today, Tidy, Duplicates, Apps, Startup, Photos, Vault, Sanitize, Consolidate, Own Your Data, Treemap, Drives, iCloud, Automate). | `DashboardView`, `TodayView` |
| [`PalVaultView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/PalVaultView.swift) | Hardware-backed biometric Touch ID storage vault and AES-GCM encrypted file browser. | `PalVaultView` |
| [`ConfidentialSanitizerView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/ConfidentialSanitizerView.swift) | Drag-and-drop EXIF/GPS/PDF metadata inspector, clean exporter, and permanent 3-pass file shredder. | `ConfidentialSanitizerView` |
| [`DriveConsolidatorView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/DriveConsolidatorView.swift) | Cross-volume multi-drive duplicate comparator and automated backup merge planner. | `DriveConsolidatorView` |
| [`LocalArchivalHubView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/LocalArchivalHubView.swift) | Cloud subscription savings estimator ($/yr), connected local/external drive manager, and NAS SMB connector. | `LocalArchivalHubView` |
| [`DuplicateFinderView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/DuplicateFinderView.swift) | Universal duplicate file browser with folder selection, size filter, preview, report copying, and batch trashing. | `DuplicateFinderView` |
| [`AppUninstallerView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/AppUninstallerView.swift) | Installed application search, orphaned leftovers inspector, Full Disk Access advisory banner, and complete uninstallation sheet. | `AppUninstallerView`, `AppUninstallDetailSheet` |
| [`StartupManagerView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/StartupManagerView.swift) | Startup items and LaunchAgents manager with enable/disable toggles and orphan detection. | `StartupManagerView` |
| [`BrowserCleanerView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/BrowserCleanerView.swift) | Zero-risk browser cache reviewer and cleaner modal for Safari, Chrome, Brave, Firefox, Edge. | `BrowserCleanerView` |
| [`PermissionRecoverySheet.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/PermissionRecoverySheet.swift) | Interactive recovery modal for blocked items during uninstallation or trashing, with 1-click FDA settings and retry. | `PermissionRecoverySheet`, `PermissionRecoveryContext` |
| [`PhotoDeduplicatorView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/PhotoDeduplicatorView.swift) | Visual photo twin detector, screenshot sweeper, and blur/low-quality photo gallery. | `PhotoDeduplicatorView` |
| [`TreemapView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/TreemapView.swift) | Interactive color-coded treemap visualization canvas with breadcrumb history, zoom, and inspector bar. | `TreemapView` |
| [`AutomationView.swift`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/Sources/StoragePal/Views/AutomationView.swift) | Scheduled maintenance rules manager, low-space triggers, dry-run modal preview, and execution audit log. | `AutomationView`, `RuleEditSheet`, `RulePreviewSheet` |

---

## 4. Build, Packaging & Execution Guidelines

### Standard Build Check
To verify compilation without packaging:
```sh
swift build
```

### Packaging a Distribution Build
Run the packaging script to generate a signed app bundle and ZIP archive:
```sh
chmod +x scripts/package-app.sh
./scripts/package-app.sh
```
*Output Artifact*: `dist/Storage Pal.zip`

### SDK Override for Specific Toolchain Environments
If the host Mac reports mismatched Command Line Tools or Xcode SDKs:
```sh
SDKROOT_OVERRIDE=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ./scripts/package-app.sh
```

---

## 5. Development & Code Conventions

1. **Concurrency & Thread Safety**:
   - UI state mutations and macOS API calls (`NSWorkspace`, `NSOpenPanel`) must execute on `@MainActor` within `AppModel`.
   - File system scanning is decoupled inside `StorageScanner` (`actor`) to keep the UI completely responsive.
   - Long-running tasks use Swift `Task` handle cancellation explicitly (`Task.isCancelled`).

2. **File System Safety**:
   - Never use direct unrecoverable file deletion (`FileManager.default.removeItem(at:)`) on candidate files. Always use `trashItem`.
   - Before moving files to external volumes during archiving, generate collision-free destination URLs (`uniqueDestination(for:in:)`).

3. **System Integration & Deeplinks**:
   - Use standard System Settings URL schemes for macOS (e.g., `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, `com.apple.settings.Storage`, `com.apple.systempreferences.AppleIDSettings?iCloud`).

4. **UI Styling**:
   - Maintain the custom design system in `Components.swift`. Avoid raw system default colors where custom `.pal*` design tokens apply.
   - Design for light mode aesthetics with subtle translucent glassmorphism effects (`.background(.white.opacity(0.82))`).
