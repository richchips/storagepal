# Changelog

All notable changes to **Storage Pal** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
## [0.16.0] - 2026-08-25

### Added
- **AI Watermark & Steganography Purifier (`AIWatermarkSanitizerService` & `ConfidentialSanitizerView`)**:
  - **Zero-Width Steganography Stripper**: Detects and eliminates hidden `U+200B` (Zero-Width Space), `U+200C` (Non-Joiner), `U+200D` (Joiner), `U+FEFF` (BOM/No-Break Space), `U+2060` (Word Joiner), `U+00AD` (Soft Hyphen), and BiDi direction controls (`U+200E`, `U+200F`, `U+202A`–`U+202E`, `U+2066`–`U+2069`).
  - **Variation Selector Eliminator**: Strips steganographic bit sequences encoded in Unicode Variation Selectors (`U+FE00`–`U+FE0F`, `U+E0100`–`U+E01EF`).
  - **Homoglyph & Confusable Normalizer**: Identifies covert Cyrillic/Greek lookalikes (`а`, `е`, `о`, `р`, `с`, `у`, `х`, `і`, `А`, `В`, `Е`, `К`, `М`, `Н`, `О`, `Р`, `С`, `Т`, `Х`) injected into English words and restores standard ASCII/Latin characters with NFKC canonical normalization.
  - **AI Chatbot Artifact & Preamble Remover**: Automatically detects and trims canned LLM intros (*"As an AI language model..."*, *"Certainly! Here is..."*, *"Sure, here is the..."*) and conversational sign-offs (*"I hope this helps!"*, *"Let me know if you have any questions."*).
  - **Interactive Text Scratchpad**: Real-time watermark detector badge (*"100% Watermark-Free"* vs *"X AI Watermark(s) Detected with Y% confidence"*), category summary pills, side-by-side visualizer highlighting hidden markers (`[ZW-SPACE]`, `[VS-TAG]`, `[ZW-BOM]`), and 1-click **"Copy Purified Clean Text"**.
  - **Document & PDF Cleaner**: Deep watermark stripper and metadata scrubber for `.txt`, `.md`, and `.pdf` files.
- **Fast, Streamlined In-App Auto-Updater**:
  - Direct streaming async download via `URLSession.download` for fast 1–2 second updates.
  - Detached PID-aware background replacement script and clean `exit(0)` termination ensuring immediate, reliable 1-click relaunch.

---

## [0.15.0] - 2026-08-25

### Added
- **Clinical & High-Recall De-Identification Upgrades (`DocumentRedactionEngine`)**:
  - **High-Recall Direct Identifier Detection**: Integrated Apple's `NaturalLanguage` ML named entity recognition (`NLTagger`) alongside structured clinical headers (`Client Sam R.`, `Patient: Sam R.`, `Assessor: Dr. Jane Doe`, `Dr. Smith`, `Mr. Jones`) to reliably detect full and abbreviated names (resolving false negatives on `"Sam R."`).
  - **Strict Patient ID Precision & Stop-Word Filtering**: Constrained MRN/Hospital numbers and NHS 10-digit IDs with digit requirements and clinical stop-words, preventing common words (e.g. `"record"`, `"notes"`, `"assessment"`) from triggering false positives.
  - **Preserve Clinical Meaning**: Retained medication names, dosages (`sertraline 50 mg`), symptoms, and psychometric scores (`PHQ-9`, `GAD-7`) without indiscriminate redaction.
  - **Configurable Privacy Policy Tiers (`PrivacyPolicyTier`)**:
    - 🩺 **Internal Clinical (Standard)**: Replaces direct identifiers with stable tokens; preserves clinical meaning, dates, and dosages.
    - 🔬 **External Research / Public (Strict)**: Replaces direct identifiers plus quasi-identifiers (exact dates $\rightarrow$ `[DATE_1]`, exact ages $\rightarrow$ `[AGE_1]`, specific locations $\rightarrow$ `[LOCATION_1]`).
  - **Dual Output Semantics**: Solid rasterized blackout PDF (0% extractable text) vs readable styled token badge PDF/Text with local session mapping.
  - **Entity Consistency & Idempotency**: Unified entity token map across multi-page documents and idempotency guard against re-tokenizing bracketed placeholders.
- **Single-Prompt Batch Authorization in App Cleaner (`FileTrashService` & `AppUninstallerView`)**:
  - Bundles all protected leftovers requiring elevated privileges into a single atomic authorization script.
  - 1-click **"Allow All & Clean Leftovers"** / **"Allow All & Move to Trash"** so users only confirm once with Touch ID or password.

---

## [0.14.0] - 2026-08-24

### Added
- **In-App Software Update Engine (`AppUpdateService` & `AppUpdateSheet`)**:
  - Review-first software update system querying release feeds and comparing semantic versions (`0.14.0` > `0.13.0`).
  - **Calm Update Modal Sheet (`AppUpdateSheet`)**: Displays release highlights, changelog notes, live download progress, and 1-click **"Download & Install Update"** / **"Install & Relaunch"**.
  - **Seamless Bundle Replacement & Relaunch**: Automatically downloads and stages the update `.zip`, unpacks `.app` bundle, and relaunches Storage Pal.
  - **Settings & Menu Bar Integration**:
    - **"Software Updates"** section in `SettingsView` with auto-check toggle, current version, last checked date, and manual check button.
    - **"Check for Updates…"** item in the MenuBarExtra status menu and application command menu.
    - Calm top banner in `DashboardView` when an update is available.

---

## [0.13.0] - 2026-08-24

### Added
- **Clipboard Auto-Sanitizer & Sensitive PII Guard (`ClipboardGuardService`)**:
  - Proactive background clipboard monitor detecting API keys (OpenAI `sk-...`, Anthropic `sk-ant-...`, AWS `AKIA...`, GitHub `ghp_...`), private encryption keys, credit cards (Luhn validated), and SSNs.
  - Floating alert banner on top of Dashboard offering 1-click **"Sanitize Clipboard"** or **"Encrypt to Vault"**.
  - User toggle in `SettingsView` under **Clipboard & AI Privacy Guard**.
- **LLM System Prompt Presets & Token Directives (`AIPromptRolePreset`)**:
  - Specialized AI assistant role preambles:
    - 🤖 *General AI Assistant*
    - ⚖️ *Legal Contract Counsel*
    - 📊 *Financial & Tax CPA*
    - 🩺 *Clinical Medical Assistant*
    - 💼 *HR & Talent Recruiter*
  - Automatically directs LLMs to strictly preserve `[TOKEN]` brackets verbatim throughout their analysis.
- **Visual Manual Drag-to-Redact Canvas (`ManualRedactionBox`)**:
  - Interactive canvas overlay in Redaction Studio to draw custom blackout boxes directly over non-text elements (signatures, stamps, logos, barcodes, photos).
  - Burns manual rectangles permanently into the high-DPI rasterized output PDF.

---

## [0.12.0] - 2026-08-24

### Added
- **Document Redaction Studio & Domain Templates (`DocumentRedactionEngine`)**:
  - Five domain-specific redaction templates:
    - **🏦 Financial & Tax**: SSN, UK NI, Luhn-validated Credit/Debit Cards, IBANs, and monetary sums.
    - **⚖️ Legal & Contracts**: Client/Party names, docket numbers, and settlement amounts.
    - **🩺 Medical & Health (GDPR/HIPAA)**: Patient IDs, MRNs, NHS numbers, Dates of Birth, and prescription dosages.
    - **💼 HR & Resumes**: Street addresses, phone numbers, private emails, and salary histories.
    - **🛠️ Custom Keyword & Regex**: Custom project codenames and regular expression patterns.
  - **True Structural PDF Redaction**: Permanent vector/raster text removal with zero selectable text residue behind blackouts.
- **AI Privacy Proxy & Reversible Token Swap (`AITokenSwapService` & `AITokenRestoreSheet`)**:
  - **Forward Pseudonymization**: Automatically replaces confidential values with contextual semantic tokens (`[PERSON_1]`, `[AMOUNT_1]`, `[SSN_1]`, `[BANK_ACCOUNT_1]`) and copies an AI-safe prompt.
  - **Encrypted Local Token Vault**: Securely persists token mapping sessions on-device.
  - **Reverse De-anonymization Bridge**: Modal sheet to paste AI responses or import AI documents, restoring genuine confidential values into place with 100% precision.

---

## [0.11.0] - 2026-08-23

### Added
- **Pal Vault — Biometric Encrypted Storage (`PalVaultService` & `PalVaultView`)**:
  - Hardware-backed AES-GCM-256 local encrypted vault for sensitive tax, health, legal, and financial files.
  - Touch ID and Apple Watch biometric authentication via `LocalAuthentication` and macOS Keychain.
  - Automatic vault lock on 10-minute inactivity timer and system sleep (`NSWorkspace.willSleepNotification`).
- **Confidential Document Sanitizer & Secure Shredder (`MetadataSanitizerService`, `SecureShredderService`, `ConfidentialSanitizerView`)**:
  - Drag-and-drop EXIF, GPS geolocation, camera model, author, and PDF revision history stripping.
  - Permanent DoD 3-pass cryptographic random/zero file shredder with hardware flush (`fcntl(fd, F_FULLFSYNC)`).
- **Storage Velocity Forecaster & Leak Sentinel (`StorageSentinelService`)**:
  - Real-time disk burn rate predictor ($\Delta\text{GB}/\text{day}$) calculating estimated days until SSD saturation.
  - Runaway daemon watcher catching abnormal gigabyte log spikes in `~/Library/Logs`.
- **Universal Drive Consolidator (`DriveConsolidatorService` & `DriveConsolidatorView`)**:
  - Multi-volume cross-drive duplicate finder using streaming SHA-256 chunk hashing.
  - Automated consolidation planner to merge scattered USB/Thunderbolt backup drives into a unified repository.
- **"Own Your Data" Local Archival & NAS Hub (`LocalArchivalHubService` & `LocalArchivalHubView`)**:
  - Cloud storage footprint and subscription cost calculator estimating annual recurring savings ($/year).
  - Connected external drive manager and 1-click local network (NAS SMB/NFS) share connector.

---

## [0.10.0] - 2026-08-23

### Added
- **Orphaned App Residue Sweeper (`OrphanedResidueService` & `AppUninstallerView`)**:
  - Scans `~/Library/Application Support`, `Containers`, `Group Containers`, `Caches`, and `Preferences` for residual folders left by apps uninstalled in the past.
  - Interactive "Orphaned Leftovers" segmented tab in `AppUninstallerView` with multi-select and 1-click batch trashing.
- **Startup & Background Items Manager (`StartupManagerService` & `StartupManagerView`)**:
  - Dedicated "Startup" navigation tab in `DashboardView` inspecting `~/Library/LaunchAgents` and `/Library/LaunchAgents`.
  - Automatic detection of broken/orphaned LaunchAgents whose target binaries no longer exist on disk.
  - One-click disable/enable toggle, "Show in Finder", and safe Move to Trash.
- **Zero-Risk Browser Cache & Media Bloat Sweeper (`BrowserCleanerService` & `BrowserCleanerView`)**:
  - Scans disposable disk caches across Safari, Google Chrome, Brave, Mozilla Firefox, Microsoft Edge, and Opera.
  - Zero-risk login guarantee: Preserves all cookies, keychains, and saved passwords so users are never logged out.
- **Stale System Logs & Diagnostics Cleaner (`SystemLogCleanerService`)**:
  - Identifies crash reports (`.ips`, `.crash`), spin dumps, and diagnostic logs in `~/Library/Logs` older than 14 days.
  - Seamlessly integrated into `StorageScanner` tidy recommendations.
- **Photo Quality, Screenshot & Blur Sweeper (`PhotoQualityService` & `PhotoDeduplicatorView`)**:
  - Multi-tab media center in `PhotoDeduplicatorView` supporting **Twins & Duplicates**, **Desktop & Download Screenshots**, and **Blurry / Low Exposure** photos.

---

## [0.9.0] - 2026-08-23

### Added
- **Resilient Multi-Tiered Safe Trashing Engine (`FileTrashService`)**:
  - Progressive 5-tier safe trashing architecture:
    1. Foundation `FileManager.trashItem(at:)`.
    2. File lock / immutability flag clearing (`chflags nouchg`) and write permission repair (`chmod u+rwX`).
    3. macOS Finder AppleScript mediation (`tell application "Finder" to delete ...`) triggering native Touch ID / admin authorization dialogs for protected `/Applications/` bundles.
    4. Safe elevated move to `~/.Trash` via administrator authorization for stubborn system-managed files.
    5. Structured error classification differentiating between TCC Full Disk Access restrictions, admin authorization denials, and locked files.
- **Full Disk Access Status Probe & Deep Linking (`FullDiskAccessService`)**:
  - Proactive TCC probe checking access to protected macOS sandbox directories (`~/Library/Containers`, `~/Library/Safari`).
  - Real-time `didBecomeActiveNotification` listener updating permission status instantly as soon as the user returns from System Settings.
  - Direct 1-click URL deep-linking to `Privacy_AllFiles` and `Privacy_FilesAndFolders`.
- **Interactive Permission Recovery Sheet (`PermissionRecoverySheet`)**:
  - Replaced dead-end error alerts with an actionable, calm modal sheet listing blocked items with their protection reasons.
  - 1-click **"Open System Settings"** with step-by-step guidance, **"Retry Uninstall"**, and **"Show in Finder"** actions.
- **Full Disk Access Guidance Banners**:
  - Added proactive Full Disk Access advisory banner in `AppUninstallerView`.
  - Added live Full Disk Access status card and direct shortcut buttons in `SettingsView`.

---

## [0.8.0] - 2026-08-20

### Added
- **Universal Duplicate File Finder (`DuplicateFinderService` & `DuplicateFinderView`)**:
  - Multi-stage SHA-256 deduplication engine (size grouping $\rightarrow$ streaming chunk verification) identifying identical documents, installers, archives, videos, and duplicate downloads.
  - Interactive "Duplicates" section in `DashboardView` with folder selection, minimum file size filtering (≥1MB, ≥10MB, ≥50MB, ≥100MB), side-by-side inspection, and 1-click batch cleanup.
  - Exportable duplicate report with "Copy Report" clipboard helper.
- **Diagnostic Error Logging & 1-Click Clipboard Copying (`AppErrorLogService`)**:
  - Centralized diagnostic error capture with ISO timestamps and subsystem classification.
  - Top-level dismissable error banner in `DashboardView` with prominent "Copy Error Details" button.
  - "Copy Execution Log" button in `AutomationView` for instantaneous audit export and troubleshooting.

---

## [0.7.0] - 2026-08-16

### Added
- **Interactive SwiftUI Storage Treemap (`TreemapBuilder` & `TreemapView`)**:
  - Proportional spatial treemap visualization algorithm dividing folder hierarchies into color-coded nested blocks sized by byte footprint.
  - Interactive navigation: Double-click to zoom into directories, breadcrumbs history, Quick Look preview, Show in Finder, and Move to Trash inspector actions.
- **Perceptual Photo Twin Deduplicator (`PhotoDeduplicatorService` & `PhotoDeduplicatorView`)**:
  - Apple `Vision` framework machine learning integration (`VNGenerateImageFeaturePrintRequest`) comparing image feature print distance to find near-identical photos, resized duplicates, and burst series.
  - Visual comparison gallery ranking copies and recommending keeping the best/highest-resolution photo while trashing lower-quality duplicates with 1-click batch cleanup.

---

## [0.6.0] - 2026-08-16

### Added
- **iCloud "Evict-to-Cloud" Manager (`ICloudEvictionService`)**:
  - Scanner for downloaded local iCloud Drive files consuming local SSD space.
  - Native `evictUbiquitousItem(at:)` integration allowing users to evict local bytes instantly from SSD while preserving files 100% safely in Apple's iCloud cloud storage.
  - Interactive "Downloaded Local iCloud Files" candidate list with 1-click "Evict to Cloud" in `ICloudView`.
- **Native Media & PDF Shrinker (`MediaCompressorService`)**:
  - `AVFoundation` HEVC (H.265) hardware video transcoder compressing bulky `.mov`, `.mp4`, `.m4v`, `.avi` files (saving 50%–70% disk space).
  - Quartz `PDFDocument` compressor optimizing PDF streams and embedded graphics.
  - Direct "Compress" action integrated into `FileReviewView` candidate rows.

---

## [0.5.0] - 2026-08-16

### Added
- **Smart App Uninstaller & Leftover Hunter (`AppUninstallerService`)**:
  - Application scanner discovering installed applications in `/Applications` and `~/Applications`.
  - Hidden Library leftover detector matching app bundle identifiers and names across `~/Library/Application Support`, `Containers`, `Group Containers`, `Preferences`, `Caches`, `Logs`, `Saved Application State`, and `LaunchAgents`.
  - Clean uninstallation engine moving main `.app` bundle and associated hidden Library folders safely to macOS Trash in a single batch operation.
- **Dedicated "Apps" Navigation Dashboard View (`AppUninstallerView`)**:
  - Added new `Apps` sidebar tab in `DashboardView` with live app search, total reclaimable space calculation, leftover folder count indicators, and confirmation sheet (`AppUninstallDetailSheet`).

---

## [0.4.0] - 2026-08-16

### Added
- **On-Device Smart Preference Machine Learning Engine (`StorageIntelligenceEngine`)**:
  - Privacy-first local ML model using weighted feature vectors (`StoragePreferenceModel`) tracking path categories, file extensions, file age, and file sizes.
  - Reinforcement learning feedback loop: Learns from every user action (moving candidates to Trash, Archiving, or Keeping) and dynamically tunes feature weights locally in `UserDefaults`.
  - Confidence scoring & UI badges: Annotates recommendations and candidates with visual smart confidence badges (e.g. `94% match`).
- **Pro Tools & Developer Sweeper (`DeveloperScanner`)**:
  - Dedicated background scanner identifying high-value developer & creative caches:
    - **Xcode & Swift**: `DerivedData`, `Archives`, `CoreSimulator` caches, and iOS device logs (`~/Library/Developer`).
    - **Node.js, Rust, Python & SPM**: Untouched `node_modules`, Rust Cargo `target/`, Python `.venv`, and SPM `.build` folders in projects untouched for $>30$ days.
    - **Creative Scratch Caches**: Adobe Premiere / After Effects / Final Cut Pro render caches.
    - **Orphaned Installers**: `.dmg`, `.pkg`, `.iso` files in `Downloads` or `Desktop` where the application is already installed in `/Applications`.

---

## [0.3.0] - 2026-08-16

### Added
- **Scheduled Maintenance Rules**:
  - Configurable recurring rules (Hourly, Daily, Weekly, Monthly, or Manual) to clean or archive target folders (Downloads, App Caches, or custom directories).
  - Flexible file filtering by age threshold (e.g. older than 7, 14, 30, 90 days) and minimum file size threshold (e.g. >=50 MB, >=100 MB, >=500 MB, >=1 GB, or any size).
  - Target maintenance strategies: **Move to Trash** (safe, recoverable deletion) or **Archive to Folder / External Drive** (with safe destination collision resolution).
- **Low Storage Space Trigger**:
  - User-configurable internal drive threshold (e.g. when free space drops below 15 GB, 25 GB, 50 GB).
  - Option to automatically execute active maintenance rules or issue high-priority notifications when low storage threshold is reached.
- **Dry-Run Preview System**:
  - Interactive "Preview / Dry Run" modal (`RulePreviewSheet`) showing all matching candidate files, file paths, and total reclaimable bytes before enabling or running any rule.
- **External Drive Safeguards & Execution Log**:
  - Automatic unmounted drive protection: Gracefully skips execution and records warnings if target destination drives/folders are disconnected.
  - Execution audit history (`MaintenanceLogEntry`) displaying recent runs, reclaimed bytes, low-space triggers, and warning details.
- **Dedicated "Automate" Navigation Section**:
  - Added new `Automate` sidebar tab in `DashboardView` featuring low-space trigger controls, active rule cards, rule editor sheet (`RuleEditSheet`), and execution audit history.

---

## [0.2.0] - 2026-08-16

### Added
- **Ten Highest-Leverage Improvements**:
  1. **Native Dark Mode Support**: Dynamic system color tokens (`palCream`, `palInk`, `palMist`, `palCardBackground`, `palCardBorder`, `palSidebarBackground`, `palSidebarSelection`, `palRowBackground`) adapting seamlessly to macOS Light and Dark appearances.
  2. **Batch Review & Multi-Select**: Added multi-file selection checkboxes, "Select All / Deselect All", and batch "Move Selected to Trash" / "Archive Selected" buttons in `FileReviewView`.
  3. **Quick Look Preview Integration**: Native `.quickLookPreview()` integration in `FileReviewView` for previewing files directly before trashing or archiving.
  4. **Parallel Multi-Core Scanning**: Refactored `StorageScanner` using Swift Concurrency `withTaskGroup` and thread-local `FileManager` instances, traversing top-level directories in parallel.
  5. **Dynamic Live State Updates**: Instant `ScanReport` recalculation upon file removal, updating `FolderSnapshot` byte counts and `DiskSnapshot` available bytes dynamically without requiring a rescan.
  6. **VoiceOver & Accessibility Overhaul**: Combined VoiceOver elements (`.accessibilityElement(children: .combine)`), accessibility values, `.isHeader` traits, and Dynamic Type responsive fonts.
  7. **Interactive Menu Bar Popover**: Upgraded `MenuBarExtra` to `.window` style popover featuring a mini health ring, free space gauge, top quick-win recommendations, and action controls.
  8. **Permission Warning Banner**: Added non-intrusive permission callout banner in `TodayView` when TCC-protected locations are skipped, with a direct link to macOS Privacy & Security settings.
  9. **Automated Unit Test Suite**: Added SPM `StoragePalTests` test suite verifying byte text formatting, health thresholds, potential savings calculations, and dynamic candidate removal.
  10. **Search, Filter & Sort in File Review Sheet**: Search bar, category filter pills (All, Videos, Pictures, Archives, Documents), and sorting controls (Largest, Smallest, Newest, Name A-Z) in `FileReviewView`.
- **Bug Log & Learnings**: Created [`bug_log.md`](file:///Users/richpomfret/Documents/ChatGPT/Storage%20Pal/bug_log.md) tracking thread safety, live state updates, and menu bar extra popover architecture patterns.

---

## [0.1.0] - 2026-08-16

### Added
- **Native macOS Menu Bar App**:
  - Compact menu bar extra displaying live disk space availability and quick scan status.
  - One-click launch to the main Storage Pal dashboard window.
- **Interactive Dashboard & Navigation Sidebar**:
  - **Today View**: Overall storage health indicator (Calm, Watch, Urgent), visual percentage storage ring gauge, and top recommended actions.
  - **Tidy List View**: Prioritized step-by-step review list of high-value cleanup candidates.
  - **Drives View**: Overview of internal Macintosh HD and connected external/removable storage volumes with usage capacity meters.
  - **iCloud View**: Dedicated guide for untangling local vs. cloud storage footprints, including direct links to Apple's System Settings panel.
- **Asynchronous Storage Scanner**:
  - Non-blocking directory enumerator analyzing common clutter locations (Desktop, Downloads, Documents, Movies, Pictures, Music, Trash, App Caches, and local iCloud Drive).
  - Identification of old downloads (>30 days untouched) and large files (>=100 MB and >=1 GB).
- **Safe File Action Modal (`FileReviewView`)**:
  - Review files individually with file preview metadata (name, size, modification date, path).
  - "Show in Finder" shortcut for instant file location reveal.
  - "Archive to external drive" feature utilizing `NSOpenPanel` for safe file transfer.
  - "Move to Trash" confirmation alert explaining iCloud file behavior and ensuring recoverability.
- **Preferences & System Integration**:
  - Automated scan cadence scheduling (Daily, Weekly, Manual).
  - Native macOS alerts and user notification support (`UserNotifications` framework).
  - Launch at login toggle using `ServiceManagement` (`SMAppService`).
  - Privacy and Security System Settings deep-linking for macOS permissions management.
- **Build & Packaging Tooling**:
  - Zsh build and packaging script (`scripts/package-app.sh`) generating compiled release bundle and zipped distribution archive (`dist/Storage Pal.zip`).
