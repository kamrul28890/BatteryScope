import Foundation

public enum HealthSource: String, CaseIterable, Codable, Identifiable {
    case raw, nominal, macOS
    public var id: String { rawValue }
    public var title: String {
        switch self { case .raw: return "Raw capacity"; case .nominal: return "Nominal capacity"; case .macOS: return "macOS reported" }
    }
}
public enum TemperatureSource: String, CaseIterable, Codable, Identifiable {
    case sensor, virtual
    public var id: String { rawValue }
    public var title: String { self == .sensor ? "Battery sensor" : "Virtual temperature" }
}
public enum CurrentSource: String, CaseIterable, Codable, Identifiable {
    case reported, instantaneous
    public var id: String { rawValue }
    public var title: String { self == .reported ? "Reported current" : "Instantaneous current" }
}
public enum CapacityUnit: String, CaseIterable, Codable, Identifiable {
    case mAh, Wh
    public var id: String { rawValue }
}

public struct BatteryReading: Codable, Identifiable {
    public var id: Date { date }
    public var date = Date()
    public var percent: Double?
    public var rawPercent: Double?
    public var cycles: Int?
    public var designMAh: Double?
    /// Legacy v0.1 nominal capacity, kept for history migration.
    public var fullMAh: Double?
    public var rawFullMAh: Double?
    public var nominalFullMAh: Double?
    public var remainingMAh: Double?
    public var macOSHealth: Double?
    public var macOSHealthDate: Date?
    public var temperatureC: Double?
    public var virtualTemperatureC: Double?
    public var volts: Double?
    public var amps: Double?
    public var instantAmps: Double?
    public var adapterWatts: Double?
    public var systemWatts: Double?
    public var inputWatts: Double?
    public var charging = false
    public var pluggedIn = false
    public var full = false
    public var minutesToFull: Double?
    public var minutesToEmpty: Double?
    public var fullEstimateSource: String?
    public var emptyEstimateSource: String?
    public var condition: String?
    public var faultStatus: UInt64?
    public var notChargingReason: UInt64?
    public var lowPowerMode: Bool?
    public var registrySource: String?
    public var lifetimeMinC: Double?
    public var lifetimeMaxC: Double?
    public var lifetimeAverageC: Double?
    public var lifetimeMinVolts: Double?
    public var lifetimeMaxVolts: Double?
    public var lifetimeMaxChargeAmps: Double?
    public var lifetimeMaxDischargeAmps: Double?
    /// Raw firmware counter: units aren't established across models.
    public var operatingTimeCounter: Double?
    public var temperatureSampleCount: Double?

    public init(date: Date = Date()) { self.date = date }
    public var health: Double? { health(from: .nominal) }
    public var batteryWatts: Double? { power(from: .reported) }
    public func health(from source: HealthSource) -> Double? {
        if source == .macOS { return macOSHealth }
        guard let design = designMAh, design > 0 else { return nil }
        let capacity = source == .raw ? rawFullMAh : nominalFullMAh ?? fullMAh
        return capacity.map { $0 / design * 100 }
    }
    public func temperature(from source: TemperatureSource) -> Double? {
        source == .sensor ? temperatureC : virtualTemperatureC
    }
    public func current(from source: CurrentSource) -> Double? {
        source == .reported ? amps : instantAmps
    }
    public func power(from source: CurrentSource) -> Double? {
        guard let volts, let current = current(from: source) else { return nil }
        return volts * current
    }
    public func capacityText(_ capacity: Double?, unit: CapacityUnit) -> String {
        guard let capacity else { return "Unavailable" }
        if unit == .mAh { return String(format: "%.0f mAh", capacity) }
        guard let volts else { return "Unavailable (voltage unknown)" }
        return String(format: "≈ %.2f Wh", capacity * volts / 1000)
    }
    public var state: String {
        full ? "Fully charged" : charging ? "Charging" : pluggedIn ? "Connected · not charging" : "On battery"
    }
    public var estimate: (Double?, String) {
        if full { return (nil, "Fully charged") }
        if charging { return (minutesToFull, "Until fully charged · " + (fullEstimateSource ?? "estimate unavailable")) }
        if pluggedIn { return (nil, "Connected · not charging; reason may be unavailable") }
        return (minutesToEmpty, "Remaining · " + (emptyEstimateSource ?? "estimate unavailable"))
    }
    public var warnings: [String] {
        var result: [String] = []
        if let condition, !condition.isEmpty, !["good", "normal"].contains(condition.lowercased()) {
            result.append("macOS battery condition: \(condition)")
        }
        if let faultStatus, faultStatus != 0 {
            let labels = ["External input problem", "Safety overvoltage", "Charge over-temperature", "Discharge over-temperature", "Cell imbalance", "Charge FET failure", "Discharge FET failure", "Data flush fault", "Permanent AFE communication failure", "Periodic AFE communication failure", "Charge safety overcurrent", "Discharge safety overcurrent", "Open thermistor", "Fuse blown"]
            for (bit, label) in labels.enumerated() where faultStatus & (1 << bit) != 0 { result.append("Battery-reported fault: " + label) }
            if faultStatus & ~UInt64(0x3fff) != 0 { result.append(String(format: "Additional unrecognized fault bits: 0x%llX", faultStatus & ~UInt64(0x3fff))) }
        }
        return result
    }

    public static func decode(_ p: [String: Any], powerSource: [String: Any] = [:], remainingSeconds: Double = -1, sourceName: String = "AppleSmartBattery") -> BatteryReading {
        func n(_ key: String) -> Double? { (p[key] as? NSNumber)?.doubleValue }
        func positive(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        func minutes(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 > 0 && $0 < 65535 ? $0 : nil } }
        func temperature(_ value: Double?, divisor: Double) -> Double? {
            guard let value, value.isFinite, value > 0 else { return nil }
            let c = value / divisor
            return (-30...100).contains(c) ? c : nil
        }
        func signed(_ value: Any?) -> Double? {
            guard let value = value as? NSNumber else { return nil }
            return Double(Int64(bitPattern: value.uint64Value)) / 1000
        }
        var r = BatteryReading()
        if let c = n("CurrentCapacity"), let m = positive(n("MaxCapacity")), c.isFinite, c >= 0 {
            r.percent = min(100, c / m * 100)
        }
        if let c = n("CycleCount"), c.isFinite, c >= 0, c < Double(Int.max) { r.cycles = Int(c) }
        r.designMAh = positive(n("DesignCapacity"))
        r.rawFullMAh = positive(n("AppleRawMaxCapacity"))
        r.nominalFullMAh = positive(n("NominalChargeCapacity"))
        r.fullMAh = r.nominalFullMAh
        r.remainingMAh = n("AppleRawCurrentCapacity").flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
        if let remaining = r.remainingMAh, let full = r.rawFullMAh { r.rawPercent = min(100, remaining / full * 100) }
        r.temperatureC = temperature(n("Temperature"), divisor: 100)
        r.virtualTemperatureC = temperature(n("VirtualTemperature"), divisor: 100)
        r.volts = positive(n("Voltage")).map { $0 / 1000 }
        r.amps = signed(p["Amperage"])
        r.instantAmps = signed(p["InstantAmperage"])
        r.charging = (p["IsCharging"] as? Bool) ?? (powerSource["Is Charging"] as? Bool) ?? false
        r.pluggedIn = (p["ExternalConnected"] as? Bool) ?? (powerSource["Power Source State"] as? String == "AC Power")
        r.full = (p["FullyCharged"] as? Bool) ?? false
        let adapter = p["AdapterDetails"] as? [String: Any] ?? (p["AppleRawAdapterDetails"] as? [[String: Any]])?.first
        r.adapterWatts = positive((adapter?["Watts"] as? NSNumber)?.doubleValue)
        if let telemetry = p["PowerTelemetryData"] as? [String: Any] {
            func watts(_ key: String) -> Double? {
                guard let value = (telemetry[key] as? NSNumber)?.doubleValue, value.isFinite, value >= 0 else { return nil }
                return value / 1000
            }
            r.systemWatts = watts("SystemLoad")
            r.inputWatts = watts("SystemPowerIn")
        }
        if r.charging {
            r.minutesToFull = minutes(n("AvgTimeToFull"))
            r.fullEstimateSource = r.minutesToFull == nil ? nil : "AvgTimeToFull"
            if r.minutesToFull == nil, let fallback = minutes(n("TimeRemaining")) {
                r.minutesToFull = fallback; r.fullEstimateSource = "TimeRemaining fallback"
            }
        } else if !r.pluggedIn {
            r.minutesToEmpty = minutes(remainingSeconds / 60)
            r.emptyEstimateSource = r.minutesToEmpty == nil ? nil : "IOPS estimate"
            if r.minutesToEmpty == nil, let avg = minutes(n("AvgTimeToEmpty")) { r.minutesToEmpty = avg; r.emptyEstimateSource = "AvgTimeToEmpty" }
            if r.minutesToEmpty == nil, let fallback = minutes(n("TimeRemaining")) { r.minutesToEmpty = fallback; r.emptyEstimateSource = "TimeRemaining fallback" }
        }
        r.condition = powerSource["BatteryHealth"] as? String
        r.faultStatus = (p["PermanentFailureStatus"] as? NSNumber)?.uint64Value
        r.notChargingReason = ((p["ChargerData"] as? [String: Any])?["NotChargingReason"] as? NSNumber)?.uint64Value
        r.registrySource = sourceName
        let battery = p["BatteryData"] as? [String: Any]
        let lifetime = battery?["LifetimeData"] as? [String: Any] ?? p["LifetimeData"] as? [String: Any]
        if let lifetime {
            func ln(_ key: String) -> Double? { (lifetime[key] as? NSNumber)?.doubleValue }
            r.lifetimeMinC = temperature(ln("MinimumTemperature"), divisor: 10)
            r.lifetimeMaxC = temperature(ln("MaximumTemperature"), divisor: 10)
            r.lifetimeAverageC = temperature(ln("AverageTemperature"), divisor: 10)
            r.lifetimeMinVolts = positive(ln("MinimumPackVoltage")).map { $0 / 1000 }
            r.lifetimeMaxVolts = positive(ln("MaximumPackVoltage")).map { $0 / 1000 }
            r.lifetimeMaxChargeAmps = signed(lifetime["MaximumChargeCurrent"]).map(abs)
            r.lifetimeMaxDischargeAmps = signed(lifetime["MaximumDischargeCurrent"]).map(abs)
            r.operatingTimeCounter = positive(ln("TotalOperatingTime"))
            r.temperatureSampleCount = positive(ln("TemperatureSamples"))
        }
        return r
    }
}

public func durationText(_ minutes: Double?) -> String {
    guard let m = minutes, m.isFinite, m > 0, m < Double(Int.max) / 2 else { return "Unavailable" }
    let n = Int(m.rounded())
    return n >= 60 ? "\(n / 60)h \(n % 60)m" : "\(max(1, n))m"
}
