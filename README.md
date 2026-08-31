# Storage Pal

**Storage Pal** is a calm, native macOS utility built with Swift and SwiftUI for managing local and cloud storage with a review-first approach. It lives in the menu bar and dashboard window, checks the locations that collect clutter, and provides intelligent, non-destructive tidy actions.

Official GitHub Repository: [https://github.com/richchips/storagepal](https://github.com/richchips/storagepal)

---

## Key Features

- **Pulse**: A device-neutral maintenance check-in for storage headroom, disposable browser caches, startup helpers, app activity, FileVault and firewall status, with an update checklist. Each result shows measured evidence and whether it was verified, needs review, or needs a manual check. Open **Pulse → Run Pulse** or press **⌘⇧P**.
- **Activity Review**: Read-only app CPU and resident-memory snapshots, with a confirmed normal quit request. No automatic suspension, force quitting, or claims that busy apps are unnecessary.
- **Update Hub**: Routes to Software Update, App Store updates, installed apps, and Storage Pal’s own updater. Third-party app and peripheral-driver versions are not automatically verified.
- **Review-First Storage Dashboard**: Real-time capacity gauges, proactive advice, and proportional interactive Treemap visualizer.
- **Pal Vault**: Hardware-backed AES-GCM-256 encrypted local vault with Touch ID biometrics and auto-lock on sleep/inactivity.
- **Document Redaction Studio**: Domain-specific templates (Financial/Tax, Legal, Medical, HR, Custom) with true vector/raster PDF flattening (zero selectable text leakage).
- **AI Privacy Proxy (Token Swap)**: Forward pseudonymization (`[PERSON_1]`, `[AMOUNT_1]`, `[SSN_1]`) + local mapping vault + 1-click reverse de-anonymization of AI responses.
- **Proactive Clipboard PII Guard**: Detects copied API keys (OpenAI, Anthropic, AWS, GitHub), private keys, and credit cards with 1-click sanitization or vault encryption.
- **Universal Duplicate Finder**: Multi-stage streaming SHA-256 file duplicate detection and batch resolution.
- **Photo Twin Deduplicator & Screenshot Sweeper**: Perceptual visual hash duplicate finder using Apple Vision framework.
- **Complete App Uninstaller & Orphan Hunter**: Uninstalls applications and purges hidden leftovers across `~/Library/Application Support`, `Containers`, `Caches`, etc.
- **Startup Helper & Daemon Manager**: Inspects and toggles background login launch items and orphaned LaunchAgents.
- **Zero-Risk Browser Cache Cleaner**: Sweeps disposable HTTP caches across Safari, Chrome, Brave, Firefox, and Edge without touching cookies or saved passwords.
- **Permanent DoD 3-Pass Shredder**: Cryptographic multi-pass random/zero file destruction with hardware sync (`F_FULLFSYNC`).
- **Storage Velocity Forecaster**: Predicts days until SSD saturation and detects runaway log/cache explosions.
- **"Own Your Data" Archival Hub**: Estimates cloud subscription savings ($/year) and assists with local NAS (SMB/NFS) and external drive consolidation.
- **In-App Software Updater**: 1-click automatic update checker and seamless relauncher.

---

## Installation & Execution

The packaged release is available in `dist/Storage Pal.zip`.
Unzip the archive and drag **Storage Pal.app** to your `/Applications` folder.

---

## Building from Source

Requirements: macOS 14.0 (Sonoma) or newer with Swift 5.9+ / Xcode command line tools.
Running the XCTest suite requires a full Xcode installation; Command Line Tools alone may not include XCTest.

```sh
# Verify standard build
swift build

# Verify behavior and safety boundaries
swift test

# Package, codesign, and archive distribution build
./scripts/package-app.sh
```

*Output Artifact*: `dist/Storage Pal.zip`
