import Foundation
import Combine
import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController`, exposing the
/// bits SwiftUI needs.
///
/// Sparkle performs the real app update — it downloads the notarized build
/// advertised by the appcast feed (`SUFeedURL` in Info.plist), verifies its
/// EdDSA signature against `SUPublicEDKey`, installs it in place and relaunches.
/// Automatic background checks are enabled via `SUEnableAutomaticChecks`; when
/// an update is found Sparkle prompts the user (it does not install silently).
///
/// This replaces the *install* path only. `AppReleaseChecker` still powers the
/// informational "What's new" card, and `ContainerReleaseChecker` (for Apple's
/// `container` CLI) is unrelated and untouched.
@MainActor
final class UpdaterViewModel: ObservableObject {
    /// Mirrors `SPUUpdater.canCheckForUpdates` so the menu item can disable
    /// itself while a check is already in flight.
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // `startingUpdater: true` boots the updater immediately; scheduling and
        // the first-launch permission behaviour are driven by the Info.plist
        // keys (SUEnableAutomaticChecks / SUScheduledCheckInterval).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manual "Check for Updates…" — always surfaces Sparkle's UI (progress,
    /// "you're up to date", or the update prompt), matching what users expect
    /// from the menu item.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
