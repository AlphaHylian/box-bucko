import Foundation
import IOKit.ps

/// Polls the system's power source info (battery percentage + charging
/// state) so BoxBucko can comment on your Mac's battery every once in a
/// while. Purely cosmetic -- reads only, changes nothing.
final class BatteryMonitor {
    struct Reading: Equatable {
        var percentage: Int
        var isCharging: Bool
    }

    var onLowBattery: (() -> Void)?
    var onStartedCharging: (() -> Void)?
    var onFullyCharged: (() -> Void)?

    private var timer: Timer?
    private var lastReading: Reading?
    private var didWarnLowBattery = false

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let reading = Self.currentReading() else { return }
        defer { lastReading = reading }

        if reading.percentage <= 15 && !reading.isCharging {
            if !didWarnLowBattery {
                didWarnLowBattery = true
                onLowBattery?()
            }
        } else {
            didWarnLowBattery = false
        }

        if let last = lastReading {
            if reading.isCharging && !last.isCharging {
                onStartedCharging?()
            }
            if reading.percentage >= 100 && last.percentage < 100 && reading.isCharging {
                onFullyCharged?()
            }
        }
    }

    private static func currentReading() -> Reading? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let sourcesList = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sourcesList {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: AnyObject] else {
                continue
            }
            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else {
                continue
            }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let isCharging = state == kIOPSACPowerValue
            let percentage = Int((Double(current) / Double(max) * 100).rounded())
            return Reading(percentage: percentage, isCharging: isCharging)
        }
        return nil
    }
}
