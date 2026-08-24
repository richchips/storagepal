import AppKit
import SwiftUI

@MainActor
struct AppUpdateSheet: View {
    @ObservedObject private var updateService = AppUpdateService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.palMint)
                        Text("Software Update")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    Text("Stay updated with the latest performance enhancements, privacy tools, and storage cleaners.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            switch updateService.status {
            case .idle, .checking:
                checkingView

            case .upToDate(let currentVersion):
                upToDateView(version: currentVersion)

            case .updateAvailable(let release):
                updateAvailableView(release: release)

            case .downloading(let progress):
                downloadingView(progress: progress)

            case .readyToRelaunch(let stagedURL):
                readyToRelaunchView(stagedURL: stagedURL)

            case .failed(let error):
                failedView(error: error)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 380)
        .background(Color.palCream)
    }

    private var checkingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Checking for Storage Pal updates…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.palMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func upToDateView(version: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.palMint)

            Text("You're Up to Date!")
                .font(.system(size: 16, weight: .bold))

            Text("Storage Pal v\(version) is currently the newest version available.")
                .font(.system(size: 12))
                .foregroundStyle(Color.palMuted)

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func updateAvailableView(release: AppReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Version \(release.version)")
                    .font(.system(size: 15, weight: .bold))
                Text("Released \(release.releaseDate)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.palMuted)
                Spacer()
                Text("Current: v\(updateService.currentVersion)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.palMint.opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("RELEASE HIGHLIGHTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.palMuted)

                ScrollView {
                    Text(release.releaseNotes)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 160)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.palCardBorder, lineWidth: 1)
                )
            }

            Spacer()

            HStack {
                Button("Remind Me Later") {
                    dismiss()
                }
                .buttonStyle(PalButtonStyle())

                Spacer()

                Button("Download & Install Update") {
                    Task {
                        try? await updateService.downloadAndInstallUpdate(release: release)
                    }
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.palMint)

            Text("Downloading Storage Pal Update…")
                .font(.system(size: 15, weight: .bold))

            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 320)
                Text("\(Int(progress * 100))% completed")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.palMuted)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func readyToRelaunchView(stagedURL: URL) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.system(size: 42))
                .foregroundStyle(Color.palMint)

            Text("Update Ready to Install!")
                .font(.system(size: 16, weight: .bold))

            Text("Storage Pal will replace the application bundle and relaunch automatically.")
                .font(.system(size: 12))
                .foregroundStyle(Color.palMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Spacer()

            HStack {
                Button("Later") {
                    dismiss()
                }
                .buttonStyle(PalButtonStyle())

                Spacer()

                Button("Install & Relaunch Now") {
                    updateService.relaunchApp(stagedAppURL: stagedURL)
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)

            Text("Update Check Failed")
                .font(.system(size: 15, weight: .bold))

            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(Color.palMuted)

            Spacer()

            HStack {
                Spacer()
                Button("Try Again") {
                    Task {
                        await updateService.checkForUpdates(userInitiated: true)
                    }
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
