# Storage Pal - Bug Log & Learnings

This log tracks bugs, compiler issues, runtime errors, edge cases, and resolution lessons discovered during development.

---

## Log Entries

### [LOG-001] Thread Safety in Concurrent Directory Enumeration
- **Component**: `StorageScanner.swift`
- **Issue**: Converting sequential directory traversals to parallel multi-core `withTaskGroup` execution required ensuring `FileManager` instance thread safety.
- **Root Cause**: `FileManager.default` single instance can cause race conditions when shared across multiple concurrent tasks.
- **Resolution**: Converted `measureLocation` to a `nonisolated static` method that instantiates thread-local `FileManager()` objects for each worker task inside `withTaskGroup`.
- **Lesson**: Always instantiate thread-local file manager instances when executing parallel file system traversals in Swift concurrency.

---

### [LOG-002] Live State Inconsistency on Candidate Deletion
- **Component**: `AppModel.swift`
- **Issue**: Removing file candidates updated `largestFiles` and `recommendations` but left `FolderSnapshot.bytes` and `DiskSnapshot.availableBytes` at stale pre-scan values.
- **Root Cause**: `AppModel.remove(_:)` previously only filtered the candidate lists without recalculating parent folder snapshots or disk capacity.
- **Resolution**: Refactored `remove(_ candidates: [FileCandidate])` to subtract reclaimed bytes from matching `FolderSnapshot`s and add reclaimed bytes to `DiskSnapshot.availableBytes`.
- **Lesson**: Keep derived observable states synchronized across all related view model properties when executing file mutations.

---

### [LOG-003] macOS MenuBarExtra Style Upgrade
- **Component**: `StoragePalApp.swift`
- **Issue**: Standard `.menuBarExtraStyle(.menu)` restricts UI elements to basic AppKit menu items, preventing custom gauges or interactive action buttons.
- **Resolution**: Upgraded to `.menuBarExtraStyle(.window)` and created a custom `MenuBarWindowView` containing mini health ring, storage bar, quick-win recommendations, and action buttons.
- **Lesson**: `.window` style `MenuBarExtra` enables rich popover UIs in macOS 14+ SwiftUI apps while retaining compact status icon display.

---

### [LOG-004] Missing Tests Directory in Packaging Script Staging
- **Component**: `scripts/package-app.sh`
- **Issue**: `package-app.sh` failed during `swift build` with `invalid custom path 'Tests/StoragePalTests'`.
- **Root Cause**: `package-app.sh` copied `Package.swift` and `Sources` to the staging build directory but omitted the `Tests` directory.
- **Resolution**: Added `if [[ -d "$PROJECT_DIR/Tests" ]]; then ditto "$PROJECT_DIR/Tests" "$BUILD_PROJECT/Tests"; fi` to `package-app.sh`.
- **Lesson**: When staging build projects for Swift Package Manager, ensure all directories referenced in `Package.swift` targets (including `testTarget`) are copied to staging.

---

### [LOG-005] XCTest Framework Requirement for Unit Tests
- **Component**: `Tests/StoragePalTests/StoragePalTests.swift`
- **Issue**: Running `swift test` under macOS Command Line Tools reports `no such module 'XCTest'`.
- **Root Cause**: Apple bundles `XCTest.framework` exclusively inside Xcode (`/Applications/Xcode.app`), not in standalone Command Line Tools (`/Library/Developer/CommandLineTools`).
- **Resolution**: Verified that app build targets (`swift build`, `package-app.sh`) compile and bundle cleanly without XCTest dependencies. Running unit tests (`swift test`) requires full Xcode toolchain (`xcode-select -s /Applications/Xcode.app`).
- **Lesson**: Document XCTest framework dependencies for SPM test targets on host environments using standalone Apple Command Line Tools.

---

### [LOG-006] Treemap Division-by-Zero Protection in Dynamic Partitioning
- **Component**: `TreemapLayout.swift`
- **Issue**: Computing recursive slice proportions via `1.0 - (consumed / total)` could cause division by zero or negative frame dimensions when the final items accounted for all remaining weight.
- **Root Cause**: Floating-point cancellation in the denominator when total consumed bytes matched total group weight.
- **Resolution**: Re-architected partition algorithm with dynamic `remainingWeight` clamping and guaranteed `isLast` partition bounds.
- **Lesson**: Always clamp denominators and compute relative weight over remaining unallocated space rather than full group totals when slicing geometry.

---

### [LOG-007] Memory Spill Optimization in Perceptual Vision Feature Prints
- **Component**: `PhotoDeduplicatorService.swift`
- **Issue**: Decoding 100+ full-resolution 48MP photos for `VNGenerateImageFeaturePrintRequest` could cause sudden memory spikes.
- **Root Cause**: Direct `CGImageSourceCreateImageAtIndex` decodes uncompressed full-dimension bitmap buffers without immediate ARC deallocation.
- **Resolution**: Wrapped generation in `autoreleasepool` and created 512px thumbnail representations with `kCGImageSourceThumbnailMaxPixelSize`.
- **Lesson**: Use downscaled thumbnail pipelines and `autoreleasepool` when feeding bulk images into Apple `Vision` or CoreML request handlers.

---

### [LOG-008] App Leftover Safeguards for Generic/Short System App Names
- **Component**: `AppUninstallerService.swift`
- **Issue**: Leftover discovery based solely on app name could match generic system directories if an app had a common name.
- **Root Cause**: Directory matching did not check name length or reserved system directory titles.
- **Resolution**: Added minimum name length check (`appName.count >= 3`) and excluded macOS reserved directory names (`System`, `Library`, `Apple`, `Preferences`, `Caches`, etc.).
- **Lesson**: Always establish an allowlist/denylist safeguard when matching file paths across user and system Library hierarchies.
