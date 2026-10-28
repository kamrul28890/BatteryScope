import Testing
import Foundation
@testable import BatteryCore

struct BatteryReadingTests {
    @Test func testSourcesStayIndependentAndNeverFallbackSilently() throws {
        let r = BatteryReading.decode([
            "CurrentCapacity": 50, "MaxCapacity": 100, "CycleCount": 387,
            "DesignCapacity": 4000, "NominalChargeCapacity": 3600,
            "AppleRawMaxCapacity": 3200, "AppleRawCurrentCapacity": 1440,
            "Temperature": 3029, "VirtualTemperature": 2900,
            "Voltage": 12000, "Amperage": 1500, "InstantAmperage": 1700,
            "IsCharging": true, "ExternalConnected": true, "AvgTimeToFull": 160
        ])
        #expect(r.percent == 50)
        #expect(r.rawPercent == 45)
        #expect(r.health(from: .raw) == 80)
        #expect(r.health(from: .nominal) == 90)
        #expect(r.health(from: .macOS) == nil)
        #expect(abs((r.temperatureC ?? -100) - 30.29) < 0.001)
        #expect(r.virtualTemperatureC == 29)
        #expect(r.power(from: .reported) == 18)
        #expect(r.power(from: .instantaneous) == 20.4)
        #expect(r.minutesToFull == 160)
        #expect(r.fullEstimateSource == "AvgTimeToFull")
        #expect(r.minutesToEmpty == nil)
        let noNominal = BatteryReading.decode(["AppleRawMaxCapacity": 3200, "DesignCapacity": 4000])
        #expect(noNominal.health(from: .nominal) == nil)
        #expect(noNominal.health(from: .raw) == 80)
    }
    @Test func testSignedCurrentAndLifetimeUnits() {
        let r = BatteryReading.decode([
            "Amperage": NSNumber(value: UInt64(bitPattern: -1200)), "Voltage": 12000,
            "BatteryData": ["LifetimeData": ["MinimumPackVoltage": 9800, "MaximumPackVoltage": 13000, "MinimumTemperature": 50, "MaximumTemperature": 474, "AverageTemperature": 256, "MaximumDischargeCurrent": NSNumber(value: UInt64(bitPattern: -3650)), "TotalOperatingTime": 30000]]
        ])
        #expect(r.amps == -1.2)
        #expect(abs((r.batteryWatts ?? 0) + 14.4) < 0.000001)
        #expect(r.lifetimeMaxDischargeAmps == 3.65)
        #expect(r.lifetimeMinVolts == 9.8)
        #expect(r.lifetimeMaxVolts == 13)
        #expect(r.lifetimeMinC == 5)
        #expect(r.lifetimeMaxC == 47.4)
        #expect(r.lifetimeAverageC == 25.6)
        #expect(r.operatingTimeCounter == 30000)
    }
    @Test func testStateAwareEstimatePrecedenceAndUnknownSentinels() {
        let fallback = BatteryReading.decode(["IsCharging": true, "ExternalConnected": true, "AvgTimeToFull": 65535, "TimeRemaining": 90])
        #expect(fallback.minutesToFull == 90)
        #expect(fallback.fullEstimateSource == "TimeRemaining fallback")
        let discharge = BatteryReading.decode(["AvgTimeToEmpty": 100, "TimeRemaining": 110], remainingSeconds: 7200)
        #expect(discharge.minutesToEmpty == 120)
        #expect(discharge.emptyEstimateSource == "IOPS estimate")
        let dischargeFallback = BatteryReading.decode(["AvgTimeToEmpty": 65535, "TimeRemaining": 110])
        #expect(dischargeFallback.minutesToEmpty == 110)
        let paused = BatteryReading.decode(["ExternalConnected": true, "AvgTimeToFull": 45, "TimeRemaining": 60])
        #expect(paused.estimate.0 == nil)
        #expect(paused.minutesToFull == nil)
        #expect(paused.minutesToEmpty == nil)
        let missing = BatteryReading.decode(["DesignCapacity": 0, "AvgTimeToEmpty": 65535, "TimeRemaining": 65535, "Temperature": 0])
        #expect(missing.health == nil)
        #expect(missing.percent == nil)
        #expect(missing.minutesToEmpty == nil)
        #expect(missing.temperatureC == nil)
        #expect(durationText(160) == "2h 40m")
        #expect(durationText(.infinity) == "Unavailable")
    }
    @Test func testFaultsAndConditionRemainDeviceReported() {
        let r = BatteryReading.decode(["PermanentFailureStatus": UInt64((1 << 4) | (1 << 13) | (1 << 20))], powerSource: ["BatteryHealth": "Check Battery"])
        #expect(r.warnings.contains { $0.contains("Cell imbalance") })
        #expect(r.warnings.contains { $0.contains("Fuse blown") })
        #expect(r.warnings.contains { $0.contains("unrecognized") })
        #expect(r.warnings.contains { $0.contains("Check Battery") })
        #expect(BatteryReading.decode(["PermanentFailureStatus": 0], powerSource: ["BatteryHealth": "Good"]).warnings.isEmpty)
    }
    @Test func testPackNormalizationAndNoPercentAsCapacity() {
        let normalized = BatteryReader.normalize(root: ["DesignCapacity": 4000, "MaxCapacity": 100, "ExternalConnected": true], pack: ["EntryChildren": ["BatteryData": ["AppleRawMaxCapacity": 3200, "AppleRawCurrentCapacity": 1600]], "Temperature": 3100])
        let r = BatteryReading.decode(normalized.properties, sourceName: normalized.source)
        #expect(r.health(from: .raw) == 80)
        #expect(r.rawPercent == 50)
        #expect(r.nominalFullMAh == nil)
        #expect(BatteryReading.decode(["MaxCapacity": 100, "DesignCapacity": 4000]).health(from: .raw) == nil)
        #expect(r.registrySource!.contains("Pack"))
    }
    @Test func testMacOSHealthOnlyReadsExplicitHealthFields() throws {
        let flat = try PropertyListSerialization.data(fromPropertyList: ["Maximum Capacity Percent": 86, "Max Capacity": 100], format: .xml, options: 0)
        #expect(MacOSHealthReader.parse(flat) == 86)
        let nested = try PropertyListSerialization.data(fromPropertyList: ["BatteryPacks": [["MaximumCapacityPercent": 84]]], format: .xml, options: 0)
        #expect(MacOSHealthReader.parse(nested) == 84)
        let chargeOnly = try PropertyListSerialization.data(fromPropertyList: ["Max Capacity": 100, "Current Capacity": 50], format: .xml, options: 0)
        #expect(MacOSHealthReader.parse(chargeOnly) == nil)
        #expect(MacOSHealthReader.parse(Data("invalid".utf8)) == nil)
    }
    @Test func testConfigurableAlertsAndUnknownTime() {
        var s = BatterySettings(); s.alertsEnabled = true; s.lowPercent = 25; s.chargedPercent = 90; s.remainingMinutes = 45
        var r = BatteryReading(); r.percent = 24; r.minutesToEmpty = 40
        #expect(BatteryAlert.active(reading: r, settings: s) == [.low, .time])
        r.minutesToEmpty = nil
        #expect(BatteryAlert.active(reading: r, settings: s) == [.low])
        r.percent = 91; r.pluggedIn = true
        #expect(BatteryAlert.active(reading: r, settings: s) == [.charged])
        s.alertsEnabled = false
        #expect(BatteryAlert.active(reading: r, settings: s).isEmpty)
    }
    @Test func testLegacyReadingMigrationAndCSVQuoting() throws {
        var legacy = BatteryReading(); legacy.fullMAh = 3600; legacy.designMAh = 4000; legacy.condition = "Check, \"Battery\"\nsoon"
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "rawFullMAh")
        let decoded = try JSONDecoder().decode(BatteryReading.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.health(from: .nominal) == 90)
        #expect(decoded.health(from: .raw) == nil)
        #expect(BatteryCSV.readings([decoded]).contains("\"Check, \"\"Battery\"\"\nsoon\""))
        #expect(decoded.capacityText(1000, unit: .Wh) == "Unavailable (voltage unknown)")
    }
}
