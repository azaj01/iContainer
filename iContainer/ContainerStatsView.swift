import SwiftUI
import Charts

/// "Stats" tab of the container detail view.
///
/// Polls `container stats <id> --no-stream` every 3 s and renders the
/// current sample as both numeric rows and three time-series charts
/// (CPU %, memory MB, network KB/s). The chart history is cached
/// per-container in a static dictionary so leaving and re-entering the
/// tab keeps the curve intact rather than resetting to a single point.

struct ContainerStatsView: View {
    let details: ContainerDetails?
    let containerId: String
    let cpuLimit: Int?
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var stats: ContainerStats?
    @State private var isLoading = false
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?
    @State private var cpuSeries: [StatPoint] = []
    @State private var memorySeries: [StatPoint] = []
    @State private var netSeries: [StatPoint] = []
    @State private var lastNetTotalBytes: Int64?
    @State private var lastNetSampleDate: Date?

    private let refreshIntervalNanos: UInt64 = 3_000_000_000

    private struct StatsCache {
        var stats: ContainerStats?
        var cpuSeries: [StatPoint]
        var cpuSeriesIsRaw: Bool
        var memorySeries: [StatPoint]
        var netSeries: [StatPoint]
        var lastNetTotalBytes: Int64?
        var lastNetSampleDate: Date?
    }

    private static var cache: [String: StatsCache] = [:]

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 24
            let sectionInnerPadding: CGFloat = 32
            let sectionContentWidth = max(0, proxy.size.width - (horizontalPadding * 2) - sectionInnerPadding)
            let statsHeight = max(420, proxy.size.height - 180)
            let chartHeight = max(90, (statsHeight - 48) / 3)
            let infoBoxHeight = max(150, chartHeight)
            ScrollView {
                if let details = details {
                    VStack(alignment: .leading, spacing: 24) {
                        ContainerHeaderView(details: details)
                        DetailSection(title: "Resource Stats", icon: "speedometer") {
                            if let stats = stats {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        DetailRow(label: "CPU %", value: normalizedCpuPercentText(for: stats))
                                        DetailRow(label: "Memory Usage", value: stats.memoryUsage)
                                        DetailRow(label: "Net Rx/Tx", value: stats.netRxTx)
                                        DetailRow(label: "Block I/O", value: stats.blockIo)
                                        DetailRow(label: "Pids", value: stats.pids)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 18)
                                    .frame(width: sectionContentWidth * 0.33, alignment: .topLeading)
                                    .frame(minHeight: infoBoxHeight, alignment: .topLeading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                    )

                                    VStack(alignment: .leading, spacing: 12) {
                                        ChartPanel(title: "CPU %") {
                                            Chart(cpuSeries) { point in
                                                LineMark(
                                                    x: .value("Time", point.time),
                                                    y: .value("CPU %", normalizedCpuPercentValue(raw: point.value))
                                                )
                                            }
                                            .chartXScale(domain: chartDomain)
                                            .chartYScale(domain: 0...100)
                                        }
                                        .frame(height: infoBoxHeight)

                                        ChartPanel(title: "Memory (MB)") {
                                            Chart(memorySeries) { point in
                                                LineMark(
                                                    x: .value("Time", point.time),
                                                    y: .value("Memory", point.value)
                                                )
                                            }
                                            .chartXScale(domain: chartDomain)
                                        }
                                        .frame(height: chartHeight)

                                        ChartPanel(title: "Network (KB/s)") {
                                            Chart(netSeries) { point in
                                                LineMark(
                                                    x: .value("Time", point.time),
                                                    y: .value("Net KB/s", point.value)
                                                )
                                            }
                                            .chartXScale(domain: chartDomain)
                                        }
                                        .frame(height: chartHeight)
                                    }
                                    .padding()
                                    .padding(.top, -16)
                                    .padding(.trailing, 4)
                                    .frame(width: sectionContentWidth * 0.67, alignment: .leading)
                                }
                                .padding(.top, -8)
                                .frame(width: sectionContentWidth, alignment: .leading)
                                .frame(height: statsHeight)
                            } else if isLoading {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.1)
                                    Text("Loading")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 80)
                            } else {
                                Text("No stats available.")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 16)
                } else {
                    ProgressView("Loading Details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 50)
                }
            }
        }
        .onAppear {
            loadCache()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
            saveCache()
        }
    }

    private func normalizedCpuPercentText(for stats: ContainerStats) -> String {
        guard let normalized = normalizedCpuPercentValue(for: stats) else { return stats.cpuPercent }
        return String(format: "%.2f%%", normalized)
    }

    private func normalizedCpuPercentValue(for stats: ContainerStats) -> Double? {
        let rawValue = stats.cpuPercentValue ?? parsePercent(stats.cpuPercent)
        guard let cpu = rawValue else { return nil }
        let coreCount = effectiveCoreCount(for: cpu)
        return min(100, cpu / coreCount)
    }

    private func normalizedCpuPercentValue(raw cpuValue: Double) -> Double {
        let coreCount = effectiveCoreCount(for: cpuValue)
        return min(100, cpuValue / coreCount)
    }

    private func effectiveCoreCount(for cpuValue: Double) -> Double {
        if let cpuLimit, cpuLimit > 0 {
            return Double(cpuLimit)
        }
        if cpuValue > 100 {
            return Double(Int(ceil(cpuValue / 100.0)))
        }
        return 1
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                if autoRefresh {
                    await refreshStats()
                }
                try? await Task.sleep(nanoseconds: refreshIntervalNanos)
            }
        }
    }

    private func loadCache() {
        guard var cached = Self.cache[containerId] else { return }
        stats = cached.stats
        if !cached.cpuSeriesIsRaw {
            let rawFactor = effectiveCoreCount(for: cached.stats?.cpuPercentValue ?? parsePercent(cached.stats?.cpuPercent ?? "") ?? 0)
            cached.cpuSeries = cached.cpuSeries.map { StatPoint(time: $0.time, value: $0.value * rawFactor) }
            cached.cpuSeriesIsRaw = true
            Self.cache[containerId] = cached
        }
        cpuSeries = cached.cpuSeries
        memorySeries = cached.memorySeries
        netSeries = cached.netSeries
        lastNetTotalBytes = cached.lastNetTotalBytes
        lastNetSampleDate = cached.lastNetSampleDate
    }

    private func saveCache() {
        Self.cache[containerId] = StatsCache(
            stats: stats,
            cpuSeries: cpuSeries,
            cpuSeriesIsRaw: true,
            memorySeries: memorySeries,
            netSeries: netSeries,
            lastNetTotalBytes: lastNetTotalBytes,
            lastNetSampleDate: lastNetSampleDate
        )
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refreshStats() async {
        isLoading = true
        if let output = await containerManager.fetchContainerStats(containerId: containerId) {
            if let parsed = parseContainerStats(output) {
                stats = parsed
                updateSeries(with: parsed)
            } else {
                stats = nil
            }
        } else {
            stats = nil
        }
        if let cached = Self.cache[containerId] {
            applyCache(cached)
        }
        isLoading = false
    }

    private func updateSeries(with parsed: ContainerStats) {
        let updated = updateCacheSeries(
            cached: StatsCache(
                stats: parsed,
                cpuSeries: cpuSeries,
                cpuSeriesIsRaw: true,
                memorySeries: memorySeries,
                netSeries: netSeries,
                lastNetTotalBytes: lastNetTotalBytes,
                lastNetSampleDate: lastNetSampleDate
            ),
            with: parsed
        )
        applyCache(updated)
        saveCache()
    }

    private func updateCacheSeries(cached: StatsCache, with parsed: ContainerStats) -> StatsCache {
        var updated = cached
        let now = Date()
        let rawCpu = parsed.cpuPercentValue ?? parsePercent(parsed.cpuPercent) ?? 0
        updated.cpuSeries.append(StatPoint(time: now, value: rawCpu))
        if let memBytes = parsed.memoryUsageBytes {
            updated.memorySeries.append(StatPoint(time: now, value: Double(memBytes) / 1_048_576.0))
        }
        if let rx = parsed.netRxBytes, let tx = parsed.netTxBytes {
            let total = rx + tx
            if let lastTotal = updated.lastNetTotalBytes, let lastTime = updated.lastNetSampleDate {
                let deltaBytes = max(0, total - lastTotal)
                let elapsed = max(1.0, now.timeIntervalSince(lastTime))
                let kbPerSec = (Double(deltaBytes) / 1024.0) / elapsed
                updated.netSeries.append(StatPoint(time: now, value: kbPerSec))
            } else {
                updated.netSeries.append(StatPoint(time: now, value: 0))
            }
            updated.lastNetTotalBytes = total
            updated.lastNetSampleDate = now
        }
        let retentionCutoff = now.addingTimeInterval(-600)
        updated.cpuSeries = updated.cpuSeries.filter { $0.time >= retentionCutoff }
        updated.memorySeries = updated.memorySeries.filter { $0.time >= retentionCutoff }
        updated.netSeries = updated.netSeries.filter { $0.time >= retentionCutoff }
        return updated
    }

    private func applyCache(_ cached: StatsCache) {
        stats = cached.stats
        cpuSeries = cached.cpuSeries
        memorySeries = cached.memorySeries
        netSeries = cached.netSeries
        lastNetTotalBytes = cached.lastNetTotalBytes
        lastNetSampleDate = cached.lastNetSampleDate
    }

    private var chartDomain: ClosedRange<Date> {
        let now = Date()
        let earliest = now.addingTimeInterval(-300)
        let minTime = [
            cpuSeries.first?.time,
            memorySeries.first?.time,
            netSeries.first?.time
        ].compactMap { $0 }.min() ?? now
        let start = max(earliest, minTime)
        return start...now
    }
}

// MARK: - Chart chrome

/// Boxed wrapper that gives each `Chart` a title and a subtle outline so
/// the three series visually line up. Generic over the chart content so
/// each panel can pass its own `Chart { LineMark(...) }` block.
private struct ChartPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Model

struct ContainerStats: Equatable {
    let cpuPercent: String
    let memoryUsage: String
    let pids: String
    let netRxTx: String
    let blockIo: String
    let cpuPercentValue: Double?
    let memoryUsageBytes: Int64?
    let netRxBytes: Int64?
    let netTxBytes: Int64?
}

struct StatPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

private struct ColumnRange {
    let start: Int
    let end: Int
}

// MARK: - Parsing

/// Parses the JSON-or-table output of `container stats`. Tries JSON first
/// (array or single object), falls back to the columnar text format.
func parseContainerStats(_ output: String) -> ContainerStats? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let data = trimmed.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data, options: []) {
        if let array = json as? [[String: Any]], let first = array.first {
            return statsFromDict(first)
        } else if let dict = json as? [String: Any] {
            return statsFromDict(dict)
        }
    }
    return statsFromTable(trimmed)
}

private func statsFromDict(_ dict: [String: Any]) -> ContainerStats? {
    let cpu = inspectStringIn(dict, keys: ["cpu", "cpuPercent", "cpu_percent", "cpuPct"]) ?? "-"
    let cpuValue = parsePercent(cpu)
    let memUsageBytes = inspectInt64In(dict, keys: ["memoryUsageBytes", "memUsageBytes"])
    let memLimitBytes = inspectInt64In(dict, keys: ["memoryLimitBytes", "memLimitBytes"])
    let memUsage = formatUsageAndLimit(usageBytes: memUsageBytes, limitBytes: memLimitBytes)
        ?? inspectStringIn(dict, keys: ["memUsage", "memoryUsage", "mem_usage", "memory"])
        ?? "-"
    let pids = inspectStringIn(dict, keys: ["pids", "numProcesses", "processes"]) ?? "-"
    let netRxBytes = inspectInt64In(dict, keys: ["networkRxBytes", "netRxBytes", "rxBytes"])
    let netTxBytes = inspectInt64In(dict, keys: ["networkTxBytes", "netTxBytes", "txBytes"])
    let netRxTx = formatRxTx(rxBytes: netRxBytes, txBytes: netTxBytes)
        ?? inspectStringIn(dict, keys: ["netRx", "networkRx", "rx", "net_rx"])
        ?? "-"
    let blkReadBytes = inspectInt64In(dict, keys: ["blockReadBytes", "blkReadBytes", "readBytes"])
    let blkWriteBytes = inspectInt64In(dict, keys: ["blockWriteBytes", "blkWriteBytes", "writeBytes"])
    let blockIo = formatRxTx(rxBytes: blkReadBytes, txBytes: blkWriteBytes)
        ?? inspectStringIn(dict, keys: ["blockRead", "blkRead", "block_read"])
        ?? "-"
    return ContainerStats(
        cpuPercent: cpu,
        memoryUsage: memUsage,
        pids: pids,
        netRxTx: netRxTx,
        blockIo: blockIo,
        cpuPercentValue: cpuValue,
        memoryUsageBytes: memUsageBytes,
        netRxBytes: netRxBytes,
        netTxBytes: netTxBytes
    )
}

private func statsFromTable(_ output: String) -> ContainerStats? {
    let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard lines.count >= 2 else { return nil }
    let header = lines[0]
    let valueLine = lines[1]
    let columnNames = ["Container ID", "Cpu %", "Memory Usage", "Net Rx/Tx", "Block I/O", "Pids"]
    let ranges = columnRanges(in: header, columns: columnNames)
    guard !ranges.isEmpty else { return nil }
    var map: [String: String] = [:]
    for (name, range) in ranges {
        let value = substring(valueLine, startOffset: range.start, endOffset: range.end)
            .trimmingCharacters(in: .whitespaces)
        map[name.lowercased()] = value
    }
    let cpu = map["cpu %"] ?? map["cpu%"] ?? "-"
    let cpuValue = parsePercent(cpu)
    let mem = map["memory usage"] ?? map["memusage"] ?? "-"
    let net = map["net rx/tx"] ?? map["netrx/tx"] ?? "-"
    let block = map["block i/o"] ?? map["block i/o"] ?? "-"
    let pids = map["pids"] ?? "-"
    let memBytes = parseUsageAndLimit(mem)?.usage
    let netBytes = parseRxTx(net)
    return ContainerStats(
        cpuPercent: cpu,
        memoryUsage: mem,
        pids: pids,
        netRxTx: net,
        blockIo: block,
        cpuPercentValue: cpuValue,
        memoryUsageBytes: memBytes,
        netRxBytes: netBytes?.rx,
        netTxBytes: netBytes?.tx
    )
}

private func columnRanges(in header: String, columns: [String]) -> [String: ColumnRange] {
    var starts: [(name: String, offset: Int)] = []
    for name in columns {
        if let range = header.range(of: name) {
            let offset = header.distance(from: header.startIndex, to: range.lowerBound)
            starts.append((name, offset))
        }
    }
    let sorted = starts.sorted { $0.offset < $1.offset }
    var result: [String: ColumnRange] = [:]
    for (idx, item) in sorted.enumerated() {
        let start = item.offset
        let end = (idx + 1 < sorted.count) ? sorted[idx + 1].offset : header.count
        result[item.name] = ColumnRange(start: start, end: end)
    }
    return result
}

private func substring(_ text: String, startOffset: Int, endOffset: Int) -> String {
    let safeStart = max(0, min(startOffset, text.count))
    let safeEnd = max(safeStart, min(endOffset, text.count))
    let startIndex = text.index(text.startIndex, offsetBy: safeStart)
    let endIndex = text.index(text.startIndex, offsetBy: safeEnd)
    return String(text[startIndex..<endIndex])
}

private func formatUsageAndLimit(usageBytes: Int64?, limitBytes: Int64?) -> String? {
    guard let usageBytes else { return nil }
    let usage = ByteCountFormatter.string(fromByteCount: usageBytes, countStyle: .memory)
    if let limitBytes {
        let limit = ByteCountFormatter.string(fromByteCount: limitBytes, countStyle: .memory)
        return "\(usage) / \(limit)"
    }
    return usage
}

private func formatRxTx(rxBytes: Int64?, txBytes: Int64?) -> String? {
    guard let rxBytes, let txBytes else { return nil }
    let rx = ByteCountFormatter.string(fromByteCount: rxBytes, countStyle: .file)
    let tx = ByteCountFormatter.string(fromByteCount: txBytes, countStyle: .file)
    return "\(rx) / \(tx)"
}

func parsePercent(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed.replacingOccurrences(of: "%", with: "")
    return Double(cleaned)
}

private func parseUsageAndLimit(_ text: String) -> (usage: Int64, limit: Int64?)? {
    let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let usage = parseSizeToBytes(parts.first) else { return nil }
    let limit = parts.count > 1 ? parseSizeToBytes(parts[1]) : nil
    return (usage, limit)
}

private func parseRxTx(_ text: String) -> (rx: Int64, tx: Int64)? {
    let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count >= 2,
          let rx = parseSizeToBytes(parts[0]),
          let tx = parseSizeToBytes(parts[1]) else { return nil }
    return (rx, tx)
}

private func parseSizeToBytes(_ text: String?) -> Int64? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let tokens = trimmed.split(separator: " ")
    guard let numberPart = tokens.first, let value = Double(numberPart) else { return nil }
    let unit = tokens.count > 1 ? tokens[1].lowercased() : "b"
    let multiplier: Double
    switch unit {
    case "kb", "kib":
        multiplier = 1024
    case "mb", "mib":
        multiplier = 1024 * 1024
    case "gb", "gib":
        multiplier = 1024 * 1024 * 1024
    case "tb", "tib":
        multiplier = 1024 * 1024 * 1024 * 1024
    default:
        multiplier = 1
    }
    return Int64(value * multiplier)
}
