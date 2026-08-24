import AppKit
import CryptoKit
import Foundation
import LocalAuthentication
import Security

@MainActor
final class PalVaultService: ObservableObject {
    static let shared = PalVaultService()

    @Published private(set) var lockState: VaultLockState = .locked
    @Published private(set) var entries: [VaultEntry] = []
    @Published private(set) var statusMessage: String?

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var encryptionKey: SymmetricKey?
    private var autoLockTask: Task<Void, Never>?

    private var vaultDirectory: URL {
        let appSupport = home.appendingPathComponent("Library/Application Support/com.storagepal.mac/PalVault")
        if !fm.fileExists(atPath: appSupport.path) {
            try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }

    private var filesDirectory: URL {
        let dir = vaultDirectory.appendingPathComponent("Files")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var manifestURL: URL {
        vaultDirectory.appendingPathComponent("manifest.json")
    }

    private let keychainService = "com.storagepal.mac.vault.key"
    private let keychainAccount = "StoragePalVaultMasterKey"

    init() {
        setupSleepObserver()
        loadManifest()
    }

    // MARK: - Lock / Unlock Flow

    func unlockWithBiometrics() async -> Bool {
        lockState = .authenticating
        statusMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?

        let canAuth = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        guard canAuth else {
            // Fallback: derive or fetch key directly if local auth policy unavailable
            return unlockWithKey()
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your encrypted Storage Pal Vault to access sensitive documents."
            )
            if success {
                let unlocked = unlockWithKey()
                resetAutoLockTimer()
                return unlocked
            } else {
                lockState = .locked
                statusMessage = "Authentication was canceled."
                return false
            }
        } catch {
            lockState = .locked
            statusMessage = "Authentication failed: \(error.localizedDescription)"
            return false
        }
    }

    func lock() {
        autoLockTask?.cancel()
        autoLockTask = nil
        encryptionKey = nil
        lockState = .locked
        statusMessage = nil

        // Clean up any decrypted preview files in temporary directory
        let tempDir = fm.temporaryDirectory.appendingPathComponent("StoragePalVaultPreview", isDirectory: true)
        if fm.fileExists(atPath: tempDir.path) {
            try? fm.removeItem(at: tempDir)
        }
    }

    // MARK: - File Import & Export

    func importFile(from sourceURL: URL, deleteSource: Bool = false) async throws {
        guard let key = encryptionKey, lockState == .unlocked else {
            throw NSError(domain: "PalVault", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vault is locked."])
        }

        let fileData = try Data(contentsOf: sourceURL)
        let sealedBox = try AES.GCM.seal(fileData, using: key)
        guard let encryptedData = sealedBox.combined else {
            throw NSError(domain: "PalVault", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encrypt file data."])
        }

        let fileID = UUID().uuidString
        let destURL = filesDirectory.appendingPathComponent("\(fileID).enc")
        try encryptedData.write(to: destURL, options: .atomic)

        let entry = VaultEntry(
            id: fileID,
            name: sourceURL.lastPathComponent,
            originalSize: Int64(fileData.count),
            encryptedSize: Int64(encryptedData.count),
            addedDate: Date(),
            fileExtension: sourceURL.pathExtension.lowercased(),
            relativeStoragePath: "\(fileID).enc"
        )

        entries.insert(entry, at: 0)
        saveManifest()
        resetAutoLockTimer()

        if deleteSource {
            _ = FileTrashService.shared.trashItem(at: sourceURL)
        }
    }

    func exportFile(entry: VaultEntry, to destinationDirectoryURL: URL) throws -> URL {
        guard let key = encryptionKey, lockState == .unlocked else {
            throw NSError(domain: "PalVault", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vault is locked."])
        }

        let encryptedFileURL = filesDirectory.appendingPathComponent(entry.relativeStoragePath)
        guard fm.fileExists(atPath: encryptedFileURL.path) else {
            throw NSError(domain: "PalVault", code: 3, userInfo: [NSLocalizedDescriptionKey: "Encrypted file not found on disk."])
        }

        let encryptedData = try Data(contentsOf: encryptedFileURL)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        let targetURL = destinationDirectoryURL.appendingPathComponent(entry.name)
        try decryptedData.write(to: targetURL, options: .atomic)

        resetAutoLockTimer()
        return targetURL
    }

    func decryptedTempURL(for entry: VaultEntry) throws -> URL {
        guard let key = encryptionKey, lockState == .unlocked else {
            throw NSError(domain: "PalVault", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vault is locked."])
        }

        let encryptedFileURL = filesDirectory.appendingPathComponent(entry.relativeStoragePath)
        let encryptedData = try Data(contentsOf: encryptedFileURL)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        let tempDir = fm.temporaryDirectory.appendingPathComponent("StoragePalVaultPreview", isDirectory: true)
        if !fm.fileExists(atPath: tempDir.path) {
            try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }

        let tempFileURL = tempDir.appendingPathComponent(entry.name)
        try decryptedData.write(to: tempFileURL, options: .atomic)
        return tempFileURL
    }

    func deleteFile(entry: VaultEntry) {
        let encryptedFileURL = filesDirectory.appendingPathComponent(entry.relativeStoragePath)
        _ = FileTrashService.shared.trashItem(at: encryptedFileURL)
        entries.removeAll { $0.id == entry.id }
        saveManifest()
        resetAutoLockTimer()
    }

    // MARK: - Key Management (Keychain)

    private func unlockWithKey() -> Bool {
        if let key = getOrCreateMasterKey() {
            self.encryptionKey = key
            self.lockState = .unlocked
            self.loadManifest()
            return true
        } else {
            self.lockState = .locked
            self.statusMessage = "Could not access or generate encryption key."
            return false
        }
    }

    private func getOrCreateMasterKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let keyData = item as? Data {
            return SymmetricKey(data: keyData)
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let newKeyData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: newKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return newKey
        }

        return newKey // Fallback to in-memory key for current session
    }

    // MARK: - Manifest & Sleep Observer

    private func loadManifest() {
        guard fm.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([VaultEntry].self, from: data) else {
            return
        }
        self.entries = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func setupSleepObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lock()
            }
        }
    }

    private func resetAutoLockTimer(minutes: Int = 10) {
        autoLockTask?.cancel()
        autoLockTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(minutes * 60 * 1_000_000_000))
            if !Task.isCancelled {
                self.lock()
            }
        }
    }
}
