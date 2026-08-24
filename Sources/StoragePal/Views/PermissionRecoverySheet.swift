import SwiftUI

struct PermissionRecoveryContext: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let appName: String?
    let app: InstalledApp?
    let blockedItems: [BatchTrashItemReport]
    let onRetry: (() -> Void)?
}

struct PermissionRecoverySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var fdaService = FullDiskAccessService.shared

    let context: PermissionRecoveryContext

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 580, minHeight: 500)
        .background(Color.palCream)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(context.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(context.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.palMuted)
            }

            Spacer()

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle())
        }
        .padding(20)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Full Disk Access Action Card
                PalCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: fdaService.hasFullDiskAccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(fdaService.hasFullDiskAccess ? Color.palMint : .orange)
                            Text(fdaService.hasFullDiskAccess ? "Full Disk Access Granted" : "Grant Full Disk Access to Remove Protected Files")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            if !fdaService.hasFullDiskAccess {
                                Button("Open System Settings") {
                                    fdaService.openFullDiskAccessSettings()
                                }
                                .buttonStyle(PalButtonStyle(prominent: true))
                            }
                        }

                        if !fdaService.hasFullDiskAccess {
                            Text("macOS requires Full Disk Access for any app to modify sandbox container files in ~/Library/Containers and ~/Library/Group Containers.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)

                            HStack(spacing: 14) {
                                stepIndicator(number: "1", text: "Click Open System Settings")
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                stepIndicator(number: "2", text: "Toggle Storage Pal ON")
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                stepIndicator(number: "3", text: "Click “Retry Uninstall”")
                            }
                            .padding(.top, 4)
                        } else {
                            Text("Full Disk Access is active. You can now retry moving the blocked items to Trash.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMint)
                        }
                    }
                }

                // Blocked Items List
                Text("BLOCKED ITEMS (\(context.blockedItems.count))")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.palMint)
                    .padding(.top, 4)

                VStack(spacing: 10) {
                    ForEach(context.blockedItems) { item in
                        PalCard(padding: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: item.category == "Application Bundle" ? "app.dashed" : "folder.badge.gearshape")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.orange)
                                    .frame(width: 36, height: 36)
                                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(item.name)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(ByteText.string(item.bytes))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.palMint)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.palMint.opacity(0.11), in: Capsule())
                                    }

                                    Text(item.url.path)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    if case .failure(let reason) = item.result {
                                        Text(reason.userFacingDescription)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Button("Show in Finder") {
                                    model.open(item.url)
                                }
                                .buttonStyle(PalButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            Button("Done") {
                dismiss()
            }
            .buttonStyle(PalButtonStyle())

            Spacer()

            if let onRetry = context.onRetry {
                Button("Retry Uninstall") {
                    dismiss()
                    onRetry()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
        .padding(16)
    }

    private func stepIndicator(number: String, text: String) -> some View {
        HStack(spacing: 6) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.palInk, in: Circle())
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.palInk)
        }
    }
}
