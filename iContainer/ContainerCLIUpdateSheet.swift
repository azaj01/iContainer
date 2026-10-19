import SwiftUI

/// "Update container CLI" sheet: shows the plan (version, package, install
/// method, what gets stopped), then drives `ContainerCLIUpdater` with live
/// progress and a log.
struct ContainerCLIUpdateSheet: View {
    @EnvironmentObject var updater: ContainerCLIUpdater
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var releaseChecker: ContainerReleaseChecker
    /// Start as soon as the plan is ready. Ignored when running containers
    /// would be stopped: that case waits for an explicit confirmation.
    var autoStart = false
    let onClose: () -> Void

    @State private var plan: ContainerCLIUpdater.Plan?
    @State private var planError: String?
    @State private var restartContainers = true

    private var runningContainers: [Container] { containerManager.containers.filter { $0.status == .running } }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update Apple container CLI").font(.headline)

            if let plan {
                planSummary(plan)
            } else if let planError {
                Label(planError, systemImage: "xmark.circle.fill").font(.caption).foregroundColor(.red).textSelection(.enabled)
            } else {
                HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Checking the latest release…").font(.caption).foregroundColor(.secondary) }
            }

            progressView

            if !updater.log.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(updater.log.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("END")
                        }
                        .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.small))
                    .onChange(of: updater.log.count) { _, _ in proxy.scrollTo("END", anchor: .bottom) }
                }
            }

            HStack {
                switch updater.phase {
                case .idle, .failed:
                    Button(updater.phase == .idle ? "Update Now" : "Try Again") { start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(plan == nil)
                case .downloading:
                    ProgressView().scaleEffect(0.8)
                    Button("Cancel") { updater.cancelDownload() }
                case .done:
                    EmptyView()
                default:
                    ProgressView().scaleEffect(0.8)
                    Text("Please wait — the service is being updated.").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(updater.phase.isActive ? "Working…" : "Close") { updater.reset(); onClose() }
                    .disabled(updater.phase.isActive)
            }

            Text("Downloads the signed installer package from the official GitHub release, verifies it is signed by Apple (Developer ID Installer: Apple Inc. - Containerization) and notarized, stops the container service, runs the installer through macOS's administrator prompt — iContainer never sees your password — then starts the service again. Same steps as Apple's update-container.sh, plus the signature check.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        }
        .frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity, minHeight: 420, idealHeight: 600, maxHeight: .infinity)
        .background(WindowResizeConfigurator(minSize: CGSize(width: 560, height: 420), shouldCenter: true))
        .task {
            guard plan == nil else { return }
            do {
                plan = try await updater.preparePlan()
                if autoStart, updater.phase == .idle, runningContainers.isEmpty { start() }
            } catch { planError = error.localizedDescription }
        }
    }

    private func planSummary(_ plan: ContainerCLIUpdater.Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailRow(label: "Installed", value: releaseChecker.installedVersion.map { "v\($0)" } ?? "-")
            DetailRow(label: "Latest", value: "v\(plan.version)")
            DetailRow(label: "Install method", value: plan.method.label)
            if case .package = plan.method {
                DetailRow(label: "Package", value: "\(plan.assetName) · \(ByteCountFormatter.string(fromByteCount: plan.assetSize, countStyle: .file))", isMonospaced: true)
            }
            if case .unknown = plan.method {
                Label("Couldn't tell how the CLI was installed; the installer package will be used (it installs under /usr/local).", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange)
            }
            if runningContainers.isEmpty {
                Text("No containers are running; the service will be stopped and started again.").font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Stopping the service stops \(runningContainers.count) running container\(runningContainers.count == 1 ? "" : "s"): \(runningContainers.map(\.name).joined(separator: ", ")). Press Update Now to confirm.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.orange)
                    Toggle("Start them again after the update", isOn: $restartContainers).toggleStyle(.checkbox).font(.caption)
                        .disabled(updater.phase.isActive)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    @ViewBuilder
    private var progressView: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading…").font(.caption)
                if let fraction { ProgressView(value: fraction) } else { ProgressView() }
            }
        case .verifying: phaseLine("Verifying signature…")
        case .stoppingService: phaseLine("Stopping the container service…")
        case .installing: phaseLine("Installing — enter your administrator password in the macOS prompt.")
        case .startingService: phaseLine("Starting the container service…")
        case .restartingContainers: phaseLine("Restarting containers…")
        case .done(let version):
            Label("Updated to v\(version).", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill").foregroundColor(.red).font(.caption).textSelection(.enabled)
        }
    }

    private func phaseLine(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text(text).font(.caption) }
    }

    private func start() {
        guard let plan else { return }
        Task {
            await updater.run(plan: plan, serviceManager: serviceManager, containerManager: containerManager, restartContainers: restartContainers)
            if case .done = updater.phase { await releaseChecker.checkForUpdateIfNeeded(force: true) }
        }
    }
}
