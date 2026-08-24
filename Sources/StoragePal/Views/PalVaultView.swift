import QuickLook
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct PalVaultView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var vaultService = PalVaultService.shared
    @State private var previewURL: URL?
    @State private var isTargetedForDrop = false
    @State private var deleteSourceOnImport = false
    @State private var exportSuccessMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Privacy & Security",
                        title: "Pal Vault",
                        detail: "Hardware-backed AES-GCM-256 encrypted storage for confidential health, legal, and financial files."
                    )
                    Spacer()
                    if vaultService.lockState == .unlocked {
                        Button {
                            vaultService.lock()
                        } label: {
                            Label("Lock Vault", systemImage: "lock.fill")
                        }
                        .buttonStyle(PalButtonStyle())
                    }
                }

                if vaultService.lockState == .locked || vaultService.lockState == .authenticating {
                    lockedStateView
                } else {
                    unlockedStateView
                }
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .quickLookPreview($previewURL)
    }

    // MARK: - Locked State View

    private var lockedStateView: some View {
        PalCard(padding: 32) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.palMint.opacity(0.12))
                        .frame(width: 84, height: 84)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.palMint)
                }

                VStack(spacing: 6) {
                    Text("Pal Vault is Locked")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Encrypted with AES-GCM 256-bit keys. Keys are isolated in your macOS Keychain and never touch the cloud.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.palMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                if let msg = vaultService.statusMessage {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                Button {
                    Task {
                        _ = await vaultService.unlockWithBiometrics()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "touchid")
                            .font(.system(size: 16))
                        Text("Unlock with Touch ID")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PalButtonStyle(prominent: true))
                .disabled(vaultService.lockState == .authenticating)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Unlocked State View

    private var unlockedStateView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary Banner
            let totalBytes = vaultService.entries.reduce(0) { $0 + $1.originalSize }
            PalCard(padding: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Vault Unlocked")
                                .font(.system(size: 14, weight: .bold))
                            Text("\(vaultService.entries.count) encrypted files (\(ByteText.string(totalBytes)))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.palMint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.palMint.opacity(0.12), in: Capsule())
                        }
                        Text("Auto-locks after 10 minutes of inactivity or whenever your Mac sleeps.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.palMuted)
                    }

                    Spacer()

                    Button {
                        chooseFileToImport()
                    } label: {
                        Label("Import File…", systemImage: "plus")
                    }
                    .buttonStyle(PalButtonStyle(prominent: true))
                }
            }

            if let msg = exportSuccessMessage {
                PalCard(padding: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.palMint)
                        Text(msg)
                            .font(.system(size: 12))
                        Spacer()
                        Button { exportSuccessMessage = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Drop zone
            dropZone

            if vaultService.entries.isEmpty {
                PalCard {
                    HStack(spacing: 20) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.palMint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Files in Vault")
                                .font(.system(size: 15, weight: .bold))
                            Text("Drag and drop confidential tax forms, passport scans, medical records, or sensitive contracts here to encrypt them.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                fileList
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isTargetedForDrop ? Color.palMint : Color.palCardBorder,
                style: StrokeStyle(lineWidth: 2, dash: [6])
            )
            .background(
                (isTargetedForDrop ? Color.palMint.opacity(0.08) : Color.clear),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .frame(height: 80)
            .overlay(
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isTargetedForDrop ? Color.palMint : Color.palMuted)
                    Text("Drop confidential files here to encrypt & store safely in Pal Vault")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isTargetedForDrop ? Color.palMint : Color.palMuted)
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleDroppedProviders(providers)
                return true
            }
    }

    private var fileList: some View {
        VStack(spacing: 10) {
            ForEach(vaultService.entries) { entry in
                PalCard(padding: 14) {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.doc.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.palMint)
                            .frame(width: 40, height: 40)
                            .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(entry.name)
                                    .font(.system(size: 13, weight: .bold))
                                Text(ByteText.string(entry.originalSize))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.palMuted)
                            }
                            Text("Encrypted with AES-GCM on \(entry.addedDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.palMuted)
                        }

                        Spacer()

                        Button {
                            previewEntry(entry)
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }
                        .buttonStyle(PalButtonStyle())

                        Button("Export…") {
                            exportEntry(entry)
                        }
                        .buttonStyle(PalButtonStyle())

                        Button {
                            vaultService.deleteFile(entry: entry)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func chooseFileToImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Encrypt to Vault"
        if panel.runModal() == .OK {
            for url in panel.urls {
                Task {
                    try? await vaultService.importFile(from: url, deleteSource: false)
                }
            }
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    try? await vaultService.importFile(from: url, deleteSource: false)
                }
            }
        }
    }

    private func previewEntry(_ entry: VaultEntry) {
        if let tempURL = try? vaultService.decryptedTempURL(for: entry) {
            previewURL = tempURL
        }
    }

    private func exportEntry(_ entry: VaultEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Decrypted Copy"
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                let exportedURL = try vaultService.exportFile(entry: entry, to: dest)
                exportSuccessMessage = "Exported “\(entry.name)” to \(exportedURL.deletingLastPathComponent().lastPathComponent)."
            } catch {
                exportSuccessMessage = "Failed to export: \(error.localizedDescription)"
            }
        }
    }
}
