import Foundation
import Combine

/// Rolling per-container history of resource samples, collected in the
/// background for every running container so the Stats tab already shows a
/// populated chart when opened — even if the container has been running for
/// a while before the user navigated to it.
///
/// Sampling is driven by `ContainerizationWrapper` (its polling loop samples
/// every running container; the open Stats tab also samples its own
/// container for liveness). History lives in a dedicated `ObservableObject`
/// rather than on the wrapper so the frequent stats mutations don't
/// re-render the sidebar / list / menu bar that observe the wrapper.
@MainActor
final class ContainerStatsStore: ObservableObject {
    struct History {
        var latest: ContainerStats?
        /// Raw (un-normalized) CPU percentages; the view divides by core
        /// count for display so the normalization can use the live limit.
        var cpuSeries: [StatPoint] = []
        var memorySeries: [StatPoint] = []
        var netSeries: [StatPoint] = []
        var lastNetTotalBytes: Int64?
        var lastNetSampleDate: Date?
    }

    @Published private(set) var histories: [String: History] = [:]

    /// Keep a generous window so the chart's fixed five-minute span always
    /// has data plus headroom, and a "stopped then restarted" gap stays
    /// visible rather than being trimmed away.
    private let retentionSeconds: TimeInterval = 900

    func history(for id: String) -> History? { histories[id] }

    /// Records one sample for `id`. `now` is injected for testability.
    func record(stats: ContainerStats, for id: String, at now: Date = Date()) {
        var history = histories[id] ?? History()
        history.latest = stats

        let rawCpu = stats.cpuPercentValue ?? parsePercent(stats.cpuPercent) ?? 0
        history.cpuSeries.append(StatPoint(time: now, value: rawCpu))

        if let memBytes = stats.memoryUsageBytes {
            history.memorySeries.append(StatPoint(time: now, value: Double(memBytes) / 1_048_576.0))
        }

        if let rx = stats.netRxBytes, let tx = stats.netTxBytes {
            let total = rx + tx
            if let lastTotal = history.lastNetTotalBytes, let lastTime = history.lastNetSampleDate {
                // max(0, …) absorbs the counter reset that happens when a
                // container is restarted, so a restart shows 0 rather than a
                // spurious spike.
                let deltaBytes = max(0, total - lastTotal)
                let elapsed = max(1.0, now.timeIntervalSince(lastTime))
                history.netSeries.append(StatPoint(time: now, value: (Double(deltaBytes) / 1024.0) / elapsed))
            } else {
                history.netSeries.append(StatPoint(time: now, value: 0))
            }
            history.lastNetTotalBytes = total
            history.lastNetSampleDate = now
        }

        let cutoff = now.addingTimeInterval(-retentionSeconds)
        history.cpuSeries.removeAll { $0.time < cutoff }
        history.memorySeries.removeAll { $0.time < cutoff }
        history.netSeries.removeAll { $0.time < cutoff }

        histories[id] = history
    }

    /// Drops history for containers that no longer exist (e.g. deleted), so
    /// the dictionary doesn't grow without bound across a long session.
    func prune(keeping ids: Set<String>) {
        for key in histories.keys where !ids.contains(key) {
            histories.removeValue(forKey: key)
        }
    }

    /// Discards all history for `id` — called when its container stops so a
    /// later restart charts fresh instead of bridging the downtime.
    func clearHistory(for id: String) {
        histories.removeValue(forKey: id)
    }
}
