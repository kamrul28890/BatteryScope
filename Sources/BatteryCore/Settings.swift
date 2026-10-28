import Foundation

public struct BatterySettings: Codable, Equatable {
    public var healthSource: HealthSource = .raw
    public var temperatureSource: TemperatureSource = .sensor
    public var currentSource: CurrentSource = .instantaneous
    public var capacityUnit: CapacityUnit = .mAh
    public var refreshSeconds: Double = 10
    public var alertsEnabled = false
    public var lowPercent = 20
    public var chargedPercent = 80
    public var remainingMinutes = 30
    public var timeAlertEnabled = true
    public init() {}
}

public enum BatteryAlert: String, CaseIterable, Hashable {
    case low, charged, time
    public static func active(reading r: BatteryReading, settings s: BatterySettings) -> Set<BatteryAlert> {
        guard s.alertsEnabled else { return [] }
        var result: Set<BatteryAlert> = []
        if let percent = r.percent {
            if !r.pluggedIn && percent <= Double(s.lowPercent) { result.insert(.low) }
            if r.pluggedIn && percent >= Double(s.chargedPercent) { result.insert(.charged) }
        }
        if !r.pluggedIn, s.timeAlertEnabled, let minutes = r.minutesToEmpty, minutes <= Double(s.remainingMinutes) { result.insert(.time) }
        return result
    }
}

public struct DailySnapshot: Codable, Identifiable {
    public var id: String
    public var firstSample: Date
    public var reading: BatteryReading
    public var sampleCount: Int
    public var note: String
    public init(reading: BatteryReading, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: reading.date)
        id = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        firstSample = reading.date
        self.reading = reading
        sampleCount = 1
        note = ""
    }
    public static func record(_ reading: BatteryReading, in snapshots: inout [DailySnapshot], calendar: Calendar = .current) {
        let new = DailySnapshot(reading: reading, calendar: calendar)
        if let index = snapshots.firstIndex(where: { $0.id == new.id }) {
            snapshots[index].reading = reading
            snapshots[index].sampleCount += 1
        } else { snapshots.append(new) }
        snapshots.sort { $0.id < $1.id }
        if snapshots.count > 1827 { snapshots.removeFirst(snapshots.count - 1827) }
    }
}

public enum BatteryCSV {
    public static func escape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    public static func readings(_ readings: [BatteryReading]) -> String {
        let header = "timestamp,charge_percent,raw_charge_percent,raw_health_percent,nominal_health_percent,macos_health_percent,macos_health_timestamp,cycles,raw_full_mah,nominal_full_mah,design_mah,sensor_c,virtual_c,voltage_v,reported_a,instant_a,reported_battery_w,instant_battery_w,adapter_rating_w,system_load_w,input_w,time_to_full_min,time_to_full_source,time_to_empty_min,time_to_empty_source,condition,fault_bits,registry_source,state"
        func n(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        let iso = ISO8601DateFormatter()
        let rows = readings.map { r -> String in
            var row = [iso.string(from: r.date), n(r.percent), n(r.rawPercent)]
            row += HealthSource.allCases.map { n(r.health(from: $0)) }
            row += [r.macOSHealthDate.map { iso.string(from: $0) } ?? "", r.cycles.map(String.init) ?? ""]
            row += [n(r.rawFullMAh), n(r.nominalFullMAh ?? r.fullMAh), n(r.designMAh)]
            row += [n(r.temperatureC), n(r.virtualTemperatureC), n(r.volts), n(r.amps), n(r.instantAmps)]
            row += [n(r.power(from: .reported)), n(r.power(from: .instantaneous)), n(r.adapterWatts), n(r.systemWatts), n(r.inputWatts)]
            row += [n(r.minutesToFull), r.fullEstimateSource ?? "", n(r.minutesToEmpty), r.emptyEstimateSource ?? ""]
            row += [r.condition ?? "", r.faultStatus.map { String($0) } ?? "", r.registrySource ?? "", r.state]
            return row.map(escape).joined(separator: ",")
        }
        return header + "\n" + rows.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
    }
    public static func daily(_ snapshots: [DailySnapshot]) -> String {
        var csv = "day,raw_health_percent,nominal_health_percent,macos_health_percent,cycles,samples,note\n"
        for day in snapshots {
            var fields = [day.id]
            fields += HealthSource.allCases.map { source in day.reading.health(from: source).map { String($0) } ?? "" }
            fields += [day.reading.cycles.map(String.init) ?? "", String(day.sampleCount), day.note]
            csv += fields.map(escape).joined(separator: ",") + "\n"
        }
        return csv
    }
}
