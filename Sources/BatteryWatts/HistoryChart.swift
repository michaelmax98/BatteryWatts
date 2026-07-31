import SwiftUI
import Charts

enum HistoryMode: String, CaseIterable, Identifiable {
    case charge
    case watts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charge: return "Charge %"
        case .watts: return "Watts"
        }
    }
}

/// Compact history graph for the panel: battery level as an area chart, or
/// charge/discharge wattage as diverging bars around a zero line.
struct HistoryChart: View {
    @ObservedObject var monitor: PowerMonitor
    @Binding var modeRaw: String

    private var mode: HistoryMode {
        HistoryMode(rawValue: modeRaw) ?? .charge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("History shows", selection: $modeRaw) {
                ForEach(HistoryMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)

            if monitor.history.count < 2 {
                Text("Collecting data — the chart fills in as BatteryWatts runs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                chart
                    .frame(height: 84)
                    .contentShape(Rectangle())
                    .onTapGesture { cycle() }
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func cycle() {
        modeRaw = (mode == .charge ? HistoryMode.watts : HistoryMode.charge).rawValue
    }

    private var footer: String {
        mode == .charge
            ? "Battery level · click chart to switch"
            : "Above line: into battery · below: draw · click to switch"
    }

    @ViewBuilder
    private var chart: some View {
        if mode == .charge {
            Chart(monitor.history, id: \.time) { sample in
                AreaMark(
                    x: .value("Time", sample.time),
                    y: .value("Charge", sample.percent)
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
                    x: .value("Time", sample.time),
                    y: .value("Charge", sample.percent)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(PowerAccent.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100])
            }
            .chartXAxis(.hidden)
        } else {
            Chart {
                ForEach(wattBuckets, id: \.time) { bucket in
                    BarMark(
                        x: .value("Time", bucket.time),
                        y: .value("Watts", bucket.watts)
                    )
                    .foregroundStyle(bucket.watts >= 0 ? PowerAccent.green : PowerAccent.blue)
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .chartXAxis(.hidden)
        }
    }

    private struct WattBucket {
        let time: Date
        let watts: Double
    }

    /// Average the 30 s samples into ~3 min buckets so the bars stay readable.
    private var wattBuckets: [WattBucket] {
        let samples = monitor.history
        guard let first = samples.first else { return [] }
        let bucketSeconds: TimeInterval = 180
        var buckets: [WattBucket] = []
        var bucketStart = first.time
        var sum = 0.0
        var count = 0
        for sample in samples {
            if sample.time.timeIntervalSince(bucketStart) >= bucketSeconds, count > 0 {
                buckets.append(WattBucket(time: bucketStart, watts: sum / Double(count)))
                bucketStart = sample.time
                sum = 0
                count = 0
            }
            sum += sample.watts
            count += 1
        }
        if count > 0 {
            buckets.append(WattBucket(time: bucketStart, watts: sum / Double(count)))
        }
        return buckets
    }
}
