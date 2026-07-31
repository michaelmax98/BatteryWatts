import SwiftUI
import Charts

enum HistoryMode: String, CaseIterable, Identifiable {
    case charge
    case watts
    case health

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charge: return "Charge"
        case .watts: return "Watts"
        case .health: return "Health"
        }
    }
}

enum HistoryWindow: String, CaseIterable, Identifiable {
    case fourHours = "4h"
    case day = "24h"
    case week = "7d"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fourHours: return 4 * 3600
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        }
    }
}

/// Compact history graphs for the panel: battery level, charge/discharge
/// wattage, or the long-term health trend — with a selectable window and an
/// optional temperature overlay.
struct HistoryChart: View {
    @ObservedObject var monitor: PowerMonitor
    @Binding var modeRaw: String
    @AppStorage(DefaultsKey.historyWindow) private var windowRaw = HistoryWindow.fourHours.rawValue
    @AppStorage(DefaultsKey.showTempOverlay) private var showTempOverlay = false

    private var mode: HistoryMode {
        HistoryMode(rawValue: modeRaw) ?? .charge
    }

    private var window: HistoryWindow {
        HistoryWindow(rawValue: windowRaw) ?? .fourHours
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("History")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("History shows", selection: $modeRaw) {
                    ForEach(HistoryMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 180)
            }

            if mode != .health {
                HStack(spacing: 6) {
                    Picker("Window", selection: $windowRaw) {
                        ForEach(HistoryWindow.allCases) { window in
                            Text(window.rawValue).tag(window.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 120)
                    Spacer()
                    temperatureChip
                }
            }

            chartArea
        }
    }

    // MARK: - Temperature overlay chip

    private var temperatureChip: some View {
        Button {
            showTempOverlay.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "thermometer")
                    .font(.system(size: 8, weight: .bold))
                Text("temp")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(showTempOverlay ? Color.white : Color.secondary)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                Capsule().fill(showTempOverlay ? PowerAccent.orange : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Charts

    @ViewBuilder
    private var chartArea: some View {
        switch mode {
        case .charge:
            if monitor.history.count < 2 {
                collectingNote("Collecting data — the chart fills in as BetterBattery runs.")
            } else {
                chargeChart
                    .frame(height: 84)
                    .contentShape(Rectangle())
                    .onTapGesture { cycle() }
            }
        case .watts:
            if monitor.history.count < 2 {
                collectingNote("Collecting data — the chart fills in as BetterBattery runs.")
            } else {
                wattsChart
                    .frame(height: 84)
                    .contentShape(Rectangle())
                    .onTapGesture { cycle() }
            }
        case .health:
            if monitor.healthLog.count < 2 {
                collectingNote("Health is snapshotted daily — the trend appears after a couple of days.")
            } else {
                healthChart
                    .frame(height: 84)
            }
        }
    }

    private func collectingNote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 56)
    }

    private func cycle() {
        modeRaw = (mode == .charge ? HistoryMode.watts : HistoryMode.charge).rawValue
    }

    private var chargeChart: some View {
        let points = displayPoints()
        return Chart {
            ForEach(points, id: \.time) { point in
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Charge", point.percent)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [PowerAccent.blue.opacity(0.40), PowerAccent.blue.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Charge", point.percent)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(PowerAccent.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if showTempOverlay {
                ForEach(temperaturePoints(points), id: \.time) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Temp", point.value),
                        series: .value("Series", "temp")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(PowerAccent.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100])
        }
        .chartXAxis(.hidden)
    }

    private var wattsChart: some View {
        let points = displayPoints()
        return Chart {
            ForEach(points, id: \.time) { point in
                BarMark(
                    x: .value("Time", point.time),
                    y: .value("Watts", point.watts)
                )
                .foregroundStyle(point.watts >= 0 ? PowerAccent.green : PowerAccent.blue)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.primary.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1))
            if showTempOverlay {
                ForEach(temperaturePoints(points), id: \.time) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Temp", point.value),
                        series: .value("Series", "temp")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(PowerAccent.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing)
        }
        .chartXAxis(.hidden)
    }

    private var healthChart: some View {
        let points = monitor.healthLog.compactMap { point -> (time: Date, health: Int)? in
            guard let health = point.healthPercent else { return nil }
            return (point.date, health)
        }
        let low = max(0, (points.map(\.health).min() ?? 80) - 5)
        return Chart {
            ForEach(points, id: \.time) { point in
                LineMark(
                    x: .value("Date", point.time),
                    y: .value("Health", point.health)
                )
                .foregroundStyle(PowerAccent.green)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(
                    x: .value("Date", point.time),
                    y: .value("Health", point.health)
                )
                .foregroundStyle(PowerAccent.green)
                .symbolSize(14)
            }
        }
        .chartYScale(domain: low...100)
        .chartYAxis {
            AxisMarks(position: .trailing)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
    }

    // MARK: - Windowing and display bucketing

    private struct DisplayPoint {
        let time: Date
        let percent: Double
        let watts: Double
        let temperature: Double?
    }

    private struct OverlayPoint {
        let time: Date
        let value: Double
    }

    private func temperaturePoints(_ points: [DisplayPoint]) -> [OverlayPoint] {
        points.compactMap { point in
            point.temperature.map { OverlayPoint(time: point.time, value: $0) }
        }
    }

    /// Windowed samples, averaged into ~240 buckets when dense so both the
    /// area chart and the bars stay readable.
    private func displayPoints() -> [DisplayPoint] {
        let cutoff = Date().addingTimeInterval(-window.seconds)
        let samples = monitor.history.filter { $0.time >= cutoff }
        guard samples.count > 300, let first = samples.first else {
            return samples.map {
                DisplayPoint(time: $0.time, percent: Double($0.percent), watts: $0.watts, temperature: $0.temperature)
            }
        }

        let bucketSeconds = max(30, window.seconds / 240)
        var buckets: [DisplayPoint] = []
        var bucketStart = first.time
        var percentSum = 0.0
        var wattsSum = 0.0
        var tempSum = 0.0
        var tempCount = 0
        var count = 0

        func flush() {
            guard count > 0 else { return }
            buckets.append(DisplayPoint(
                time: bucketStart,
                percent: percentSum / Double(count),
                watts: wattsSum / Double(count),
                temperature: tempCount > 0 ? tempSum / Double(tempCount) : nil
            ))
        }

        for sample in samples {
            if sample.time.timeIntervalSince(bucketStart) >= bucketSeconds, count > 0 {
                flush()
                bucketStart = sample.time
                percentSum = 0; wattsSum = 0; tempSum = 0; tempCount = 0; count = 0
            }
            percentSum += Double(sample.percent)
            wattsSum += sample.watts
            if let temperature = sample.temperature {
                tempSum += temperature
                tempCount += 1
            }
            count += 1
        }
        flush()
        return buckets
    }
}
