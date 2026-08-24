import SwiftUI

@MainActor
struct LocalArchivalHubView: View {
    @EnvironmentObject private var model: AppModel
    @State private var cloudEstimates: [CloudSubscriptionEstimate] = []
    @State private var networkShares: [NetworkShareTarget] = []
    @State private var isShowingNASConnect = false
    @State private var nasAddress = "smb://nas.local"
    @State private var isScanning = false

    private let hubService = LocalArchivalHubService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(
                        eyebrow: "Own Your Data",
                        title: "Local Storage & Unsubscribe Hub",
                        detail: "Cut recurring cloud subscriptions and take ownership of your storage on local external SSDs and network NAS drives."
                    )
                    Spacer()
                    Button {
                        refreshData()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PalButtonStyle())
                }

                // Financial Savings Summary
                financialSavingsCard

                // Cloud Services Breakdown
                cloudServicesSection

                // Local Drives & Network Shares
                connectedStorageSection

                // Playbook Checklist
                localStoragePlaybookCard
            }
            .padding(34)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $isShowingNASConnect) {
            nasConnectSheet
        }
        .onAppear {
            refreshData()
        }
    }

    // MARK: - Financial Summary Card

    private var financialSavingsCard: some View {
        let activeEstimates = cloudEstimates.filter { $0.isDetected }
        let totalYearly = activeEstimates.reduce(0.0) { $0 + $1.estimatedYearlyCostUSD }
        let totalBytes = activeEstimates.reduce(0) { $0 + $1.usedBytes }

        return PalCard(padding: 20) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.palMint.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.palMint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("ESTIMATED CLOUD SUBSCRIPTION COST")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.palMint)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "$%.2f / year", totalYearly))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("(\(ByteText.string(totalBytes)) across \(activeEstimates.count) cloud service(s))")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.palMuted)
                    }
                    Text("Moving these files to a one-time external SSD ($80) saves you money every single year.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.palMuted)
                }
                Spacer()
            }
        }
    }

    // MARK: - Cloud Services Section

    private var cloudServicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETECTED CLOUD STORAGE FOOTPRINTS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.palMint)

            VStack(spacing: 10) {
                ForEach(cloudEstimates) { item in
                    PalCard(padding: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: item.service.symbol)
                                .font(.system(size: 20))
                                .foregroundStyle(item.isDetected ? Color.palMint : Color.palMuted)
                                .frame(width: 38, height: 38)
                                .background(
                                    (item.isDetected ? Color.palMint : Color.palMuted).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(item.service.rawValue)
                                        .font(.system(size: 13, weight: .bold))
                                    if item.isDetected {
                                        Text(String(format: "~$%.2f/mo ($%.2f/yr)", item.estimatedMonthlyCostUSD, item.estimatedYearlyCostUSD))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.palMint)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.palMint.opacity(0.12), in: Capsule())
                                    }
                                }

                                if item.isDetected {
                                    Text("\(ByteText.string(item.usedBytes)) synced on this Mac")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.palMuted)
                                } else {
                                    Text("Not actively used or under 10 MB")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            if item.isDetected {
                                Button("Show Folder") {
                                    model.open(item.localPath)
                                }
                                .buttonStyle(PalButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Connected Storage & NAS Section

    private var connectedStorageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LOCAL HARD DRIVES & NETWORK NAS SHARES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.palMint)

                Spacer()

                Button {
                    isShowingNASConnect = true
                } label: {
                    Label("Connect to NAS (SMB)…", systemImage: "network")
                }
                .buttonStyle(PalButtonStyle())
            }

            if networkShares.isEmpty {
                PalCard {
                    HStack(spacing: 16) {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.palMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No External or Network Drives Connected")
                                .font(.system(size: 13, weight: .bold))
                            Text("Plug in an external USB/Thunderbolt SSD or connect to a local SMB share to archive cloud data locally.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.palMuted)
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(networkShares) { share in
                        PalCard(padding: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: "externaldrive.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.palMint)
                                    .frame(width: 38, height: 38)
                                    .background(Color.palMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(share.name)
                                        .font(.system(size: 13, weight: .bold))
                                    if let avail = share.availableBytes, let total = share.totalBytes {
                                        Text("\(ByteText.string(avail)) free of \(ByteText.string(total))")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.palMuted)
                                    } else {
                                        Text("Mounted local/network storage")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.palMuted)
                                    }
                                }

                                Spacer()

                                Button("Open") {
                                    model.open(share.url)
                                }
                                .buttonStyle(PalButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Playbook Card

    private var localStoragePlaybookCard: some View {
        PalCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.palMint)
                    Text("The 'Own Your Data' Playbook")
                        .font(.system(size: 14, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 8) {
                    stepRow(number: "1", title: "Acquire a high-speed external SSD or local NAS", detail: "A 2 TB Samsung T7 or SanDisk Extreme costs ~$130 once vs $120/yr indefinitely.")
                    stepRow(number: "2", title: "Archive large video & photo libraries locally", detail: "Use Storage Pal's Drive Consolidator & Media Shrinker to organize historical archives.")
                    stepRow(number: "3", title: "Downgrade cloud plans to minimum tier", detail: "Keep a free or low-tier plan strictly for live mobile sync while keeping your main repo local.")
                }
            }
        }
    }

    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.palMint)
                .frame(width: 18, height: 18)
                .background(Color.palMint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.palMuted)
            }
        }
    }

    // MARK: - NAS Connect Sheet

    private var nasConnectSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Connect to Network Attached Storage (NAS)")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") { isShowingNASConnect = false }
                    .buttonStyle(PalButtonStyle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Server Address (SMB, AFP, or NFS):")
                    .font(.system(size: 12))
                TextField("smb://192.168.1.100 or smb://nas.local", text: $nasAddress)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Connect…") {
                    _ = hubService.connectToNetworkShare(urlString: nasAddress)
                    isShowingNASConnect = false
                }
                .buttonStyle(PalButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color.palCream)
    }

    // MARK: - Actions

    private func refreshData() {
        isScanning = true
        Task {
            let estimates = await hubService.scanCloudSubscriptions()
            let shares = await hubService.scanNetworkAndExternalShares()
            self.cloudEstimates = estimates
            self.networkShares = shares
            self.isScanning = false
        }
    }
}
