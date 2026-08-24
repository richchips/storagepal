import SwiftUI

@main
struct StoragePalApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Storage Pal", id: "main") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 660)
                .task { model.start() }
        }
        .defaultSize(width: 1060, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task {
                        await AppUpdateService.shared.checkForUpdates(userInitiated: true)
                    }
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Check Storage Now") { model.runScan() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra("Storage Pal", systemImage: model.statusSymbol) {
            MenuBarWindowView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 520)
        }
    }
}

private struct MenuBarWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            header
            Divider()

            if let report = model.report, let disk = report.internalDisk {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StorageBar(usedFraction: disk.usedFraction, tint: report.health.tint)
                        Text("\(Int(disk.usedFraction * 100))% used")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(report.health.tint)
                    }

                    if !report.recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("QUICK WINS")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Color.palMint)

                            ForEach(Array(report.recommendations.prefix(2))) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: item.kind.symbol)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.palMint)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        if item.reclaimableBytes > 0 {
                                            Text(ByteText.string(item.reclaimableBytes))
                                                .font(.system(size: 10))
                                                .foregroundStyle(Color.palMint)
                                        }
                                    }
                                    Spacer()
                                    Button(item.actionLabel) {
                                        openDashboard()
                                        model.handle(item)
                                    }
                                    .buttonStyle(PalButtonStyle())
                                }
                                .padding(8)
                                .background(Color.palRowBackground, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.isScanning ? model.scanMessage : "Storage check not run yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.palMuted)
                }
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button {
                    openDashboard()
                } label: {
                    Label("Open Dashboard", systemImage: "macwindow")
                }
                .buttonStyle(PalButtonStyle(prominent: true))

                Spacer()

                Button {
                    model.runScan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PalButtonStyle())
                .disabled(model.isScanning)
                .help("Check storage now")

                Button {
                    openDashboard()
                    Task {
                        await AppUpdateService.shared.checkForUpdates(userInitiated: true)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PalButtonStyle())
                .help("Check for Updates")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(PalButtonStyle())
                .help("Quit Storage Pal")
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Color.palCream)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(model.report?.health.tint.opacity(0.15) ?? Color.palMist)
                    .frame(width: 36, height: 36)
                Image(systemName: model.statusSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.report?.health.tint ?? Color.palMint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.report?.health.title ?? "Storage Pal")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                if let disk = model.report?.internalDisk {
                    Text("\(ByteText.string(disk.availableBytes)) available")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                } else {
                    Text(model.scanMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
            }
            Spacer()
        }
    }

    private func openDashboard() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
