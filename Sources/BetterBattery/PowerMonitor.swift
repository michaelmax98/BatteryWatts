import Foundation
import Combine
import IOKit
import IOKit.ps

enum PowerState: Equatable {
    case charging       // external power, energy flowing into the battery
    case discharging    // running on battery
    case charged        // plugged in, battery full
    case pluggedIdle    // plugged in, not charging (e.g. Optimized Battery Charging hold)
    case noBattery      // no internal battery found
}

struct BatterySnapshot: Equatable {
    var state: PowerState = .noBattery
    var watts: Double = 0            // instantaneous battery power; + into the battery, − out of it
    var smoothedWatts: Double = 0    // lightly smoothed copy for display
    var voltage: Double = 0          // V
    var amperage: Double = 0         // A, signed like `watts`
    var percent: Int = 0             // 0…100
    var timeToFullMinutes: Int?
    var timeToEmptyMinutes: Int?
    var adapterWatts: Int?           // negotiated adapter power while plugged in
    var healthPercent: Int?          // full-charge capacity vs design capacity
    var cycleCount: Int?
    var temperatureC: Double?        // battery temperature
    var rawCurrentmAh: Int?          // raw charge, mAh
    var rawFullmAh: Int?             // raw full-charge capacity, mAh
    var designmAh: Int?              // design capacity, mAh

    static let empty = BatterySnapshot()
}

struct PowerSample: Equatable {
    let time: Date
    let percent: Int
    let watts: Double
}

final class PowerMonitor: ObservableObject {
    static let shared = PowerMonitor()

    @Published private(set) var snapshot = BatterySnapshot.empty
    @Published private(set) var history: [PowerSample] = []
    @Published private(set) var fans: [FanReading]?
    @Published private(set) var lifetimeDischargeWh: Double = 0
    @Published private(set) var lifetimeChargeWh: Double = 0

    private var timer: Timer?
    private var smoothedWatts: Double?
    private var lastSampleAt: Date?
    private let sampleInterval: TimeInterval = 30
    private let maxSamples = 480   // 4 hours at 30 s
    private var ticksSincePersist = 0
    private var ticksSinceFans = 5

    private init() {
        lifetimeDischargeWh = UserDefaults.standard.double(forKey: DefaultsKey.lifetimeDischargeWh)
        lifetimeChargeWh = UserDefaults.standard.double(forKey: DefaultsKey.lifetimeChargeWh)
        refresh()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        var snap = BatterySnapshot.empty
        readSmartBattery(into: &snap)
        readPowerSources(into: &snap)
        readAdapter(into: &snap)

        // Light exponential smoothing so the big number doesn't jitter; reset
        // whenever the state flips or the value jumps (plug / unplug).
        if let previous = smoothedWatts,
           snap.state == snapshot.state,
           abs(previous - snap.watts) < 12 {
            smoothedWatts = previous * 0.55 + snap.watts * 0.45
        } else {
            smoothedWatts = snap.watts
        }
        snap.smoothedWatts = smoothedWatts ?? snap.watts

        snapshot = snap
        recordSample(from: snap)
        accumulateLifetime(from: snap)
        refreshFansIfDue()
    }

    /// Integrate battery power over time into all-time Wh counters (1 Hz).
    private func accumulateLifetime(from snap: BatterySnapshot) {
        guard snap.state != .noBattery else { return }
        if snap.watts < -0.05 {
            lifetimeDischargeWh += (-snap.watts) / 3600.0
        } else if snap.watts > 0.05 {
            lifetimeChargeWh += snap.watts / 3600.0
        }
        ticksSincePersist += 1
        if ticksSincePersist >= 60 {
            ticksSincePersist = 0
            UserDefaults.standard.set(lifetimeDischargeWh, forKey: DefaultsKey.lifetimeDischargeWh)
            UserDefaults.standard.set(lifetimeChargeWh, forKey: DefaultsKey.lifetimeChargeWh)
        }
    }

    private func refreshFansIfDue() {
        ticksSinceFans += 1
        guard ticksSinceFans >= 5 else { return }
        ticksSinceFans = 0
        let readings = SMCFansReader.shared.readFans()
        if readings != fans {
            fans = readings
        }
    }

    private func recordSample(from snap: BatterySnapshot) {
        guard snap.state != .noBattery else { return }
        let now = Date()
        if let last = lastSampleAt, now.timeIntervalSince(last) < sampleInterval {
            return
        }
        lastSampleAt = now
        history.append(PowerSample(time: now, percent: snap.percent, watts: snap.watts))
        if history.count > maxSamples {
            history.removeFirst(history.count - maxSamples)
        }
    }

    // MARK: - IORegistry (AppleSmartBattery): live volts × amps

    private func readSmartBattery(into snap: inout BatterySnapshot) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else { return }

        let millivolts = signedInt(props["Voltage"]) ?? 0
        let milliamps = signedInt(props["InstantAmperage"]) ?? signedInt(props["Amperage"]) ?? 0
        snap.voltage = Double(millivolts) / 1000.0
        snap.amperage = Double(milliamps) / 1000.0
        snap.watts = snap.voltage * snap.amperage

        let external = (props["ExternalConnected"] as? Bool) ?? false
        let charging = (props["IsCharging"] as? Bool) ?? false
        let full = (props["FullyCharged"] as? Bool) ?? false
        if charging {
            snap.state = .charging
        } else if external && full {
            snap.state = .charged
        } else if external {
            snap.state = .pluggedIdle
        } else {
            snap.state = .discharging
        }

        snap.cycleCount = signedInt(props["CycleCount"])

        // Health: raw full-charge capacity vs design capacity. On Apple silicon
        // `MaxCapacity` is a percentage, so prefer the raw key; the > 200 guard
        // skips percentage-valued fallbacks.
        let rawMax = signedInt(props["AppleRawMaxCapacity"]) ?? signedInt(props["MaxCapacity"]) ?? 0
        let design = signedInt(props["DesignCapacity"]) ?? 0
        if design > 0, rawMax > 200 {
            let health = Int((Double(rawMax) / Double(design) * 100).rounded())
            if health > 0 && health <= 120 {
                snap.healthPercent = min(health, 100)
            }
        }
        if rawMax > 200 { snap.rawFullmAh = rawMax }
        if design > 200 { snap.designmAh = design }
        let rawCurrent = signedInt(props["AppleRawCurrentCapacity"]) ?? 0
        if rawCurrent > 0 { snap.rawCurrentmAh = rawCurrent }

        // Battery temperature: the registry publishes centi-degrees; some
        // machines report centi-Kelvin instead, so convert when it's huge.
        if let rawTemp = signedInt(props["Temperature"]), rawTemp > 0 {
            var celsius = Double(rawTemp) / 100.0
            if celsius > 200 {
                celsius -= 273.15
            }
            if celsius > -20 && celsius < 120 {
                snap.temperatureC = celsius
            }
        }
    }

    // MARK: - IOPowerSources: percentage and system time estimates

    private func readPowerSources(into snap: inout BatterySnapshot) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let capacity = description[kIOPSMaxCapacityKey] as? Int, capacity > 0 {
                snap.percent = Int((Double(current) / Double(capacity) * 100).rounded())
            }
            if let minutes = description[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                snap.timeToFullMinutes = minutes
            }
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                snap.timeToEmptyMinutes = minutes
            }

            // Fallback when the registry read didn't resolve a state.
            if snap.state == .noBattery {
                let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
                let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                if charging {
                    snap.state = .charging
                } else if onAC {
                    snap.state = snap.percent >= 95 ? .charged : .pluggedIdle
                } else {
                    snap.state = .discharging
                }
            }
        }
    }

    private func readAdapter(into snap: inout BatterySnapshot) {
        switch snap.state {
        case .charging, .charged, .pluggedIdle:
            break
        default:
            return
        }
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = details[kIOPSPowerAdapterWattsKey] as? Int, watts > 0 else { return }
        snap.adapterWatts = watts
    }

    // MARK: - Helpers

    /// IORegistry publishes some signed battery values with 32- or 64-bit
    /// wraparound (`Amperage` reads as 18446744073709551062 while discharging).
    /// Battery magnitudes are tiny, so reinterpret the wrapped patterns.
    private func signedInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.uint64Value
        if raw > UInt64(Int64.max) {
            return Int(truncatingIfNeeded: Int64(bitPattern: raw))
        }
        let wide = Int64(raw)
        if wide >= 0x8000_0000 && wide <= 0xFFFF_FFFF {
            return Int(Int32(truncatingIfNeeded: wide))
        }
        return Int(wide)
    }
}
