import SwiftUI

struct ContainerDetailView: View {
    let containerId: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var details: ContainerDetails?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading Details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 50)
            } else if let details = details {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(details.name)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Spacer()
                            StatusBadge(status: details.status ?? "unknown")
                        }
                        Text("ID: \(details.configuration?.id ?? "-")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                    .padding(.bottom, 8)

                    // Basic Info
                    DetailSection(title: "Basic Information", icon: "info.circle") {
                        DetailRow(label: "Image", value: details.configuration?.image?.reference ?? "-")
                        DetailRow(label: "Command", value: details.command, isMonospaced: true)
                    }

                    // Network
                    DetailSection(title: "Network", icon: "network") {
                        DetailRow(label: "IP Address", value: details.networks?.first?.address ?? "-")
                        DetailRow(label: "Ports", value: details.portBindings.isEmpty ? "None" : details.portBindings.joined(separator: ", "))
                    }

                    // Mounts
                    DetailSection(title: "Mounts", icon: "externaldrive") {
                        if let mounts = details.configuration?.mounts, !mounts.isEmpty {
                            ForEach(mounts, id: \.self) { mount in
                                DetailRow(label: mount.source ?? "-", value: mount.destination ?? "-")
                            }
                        } else {
                            Text("No volumes mounted.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }

                    // Environment
                    DetailSection(title: "Environment Variables", icon: "scroll") {
                        if let env = details.configuration?.initProcess?.environment, !env.isEmpty {
                            ForEach(env, id: \.self) { envVar in
                                let parts = envVar.split(separator: "=", maxSplits: 1)
                                if parts.count == 2 {
                                    DetailRow(label: String(parts[0]), value: String(parts[1]), isMonospaced: true)
                                } else {
                                    Text(envVar)
                                        .font(.caption)
                                        .monospaced()
                                }
                            }
                        } else {
                            Text("No environment variables set.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Could not load container details.")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 50)
            }
        }
        .navigationTitle(details?.name ?? "Details")
        .task(id: containerId) {
            await loadDetails()
        }
        .onChange(of: containerManager.containers) { _, _ in
            updateDetailsFromList()
        }
    }

    private func loadDetails() async {
        if details == nil {
            details = await containerManager.inspectContainer(containerId: containerId)
            isLoading = false
        }
        updateDetailsFromList()
    }

    private func updateDetailsFromList() {
        guard let current = details,
              let match = containerManager.containers.first(where: { $0.id == containerId }) else {
            return
        }
        let statusText = match.status == .running ? "running" : "stopped"
        let updatedNetworks: [ContainerDetails.NetworkInfo]? = match.ipAddress != nil
            ? [ContainerDetails.NetworkInfo(address: match.ipAddress)]
            : current.networks
        let updatedImage: ContainerDetails.ImageInfo? = match.image != nil
            ? ContainerDetails.ImageInfo(reference: match.image)
            : current.configuration?.image
        let updatedConfiguration = ContainerDetails.ConfigurationData(
            id: current.configuration?.id,
            hostname: current.configuration?.hostname,
            image: updatedImage,
            mounts: current.configuration?.mounts,
            initProcess: current.configuration?.initProcess,
            publishedSockets: current.configuration?.publishedSockets
        )
        let updated = ContainerDetails(
            status: statusText,
            networks: updatedNetworks,
            configuration: updatedConfiguration
        )
        if updated != current {
            details = updated
        }
    }
}

// MARK: - UI Components

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(value)
                .font(isMonospaced ? .caption.monospaced() : .body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: String
    
    var color: Color {
        status.lowercased() == "running" ? .green : .red
    }
    
    var body: some View {
        Text(status.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}
