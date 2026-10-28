import Testing
import Foundation
@testable import BatteryCore

struct PersistenceTests {
    @Test func testDailySnapshotsPreserveNotesAndCountDays() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var r = BatteryReading(date: Date(timeIntervalSince1970: 1_700_000_000))
        r.rawFullMAh = 3200; r.designMAh = 4000
        var snapshots: [DailySnapshot] = []
        DailySnapshot.record(r, in: &snapshots, calendar: calendar)
        snapshots[0].note = "Replaced adapter"
        r.date.addTimeInterval(60)
        DailySnapshot.record(r, in: &snapshots, calendar: calendar)
        #expect(snapshots.count == 1)
        #expect(snapshots[0].sampleCount == 2)
        #expect(snapshots[0].note == "Replaced adapter")
        r.date.addTimeInterval(86400)
        DailySnapshot.record(r, in: &snapshots, calendar: calendar)
        #expect(snapshots.count == 2)
        let restored = try JSONDecoder().decode([DailySnapshot].self, from: JSONEncoder().encode(snapshots))
        #expect(restored[0].note == "Replaced adapter")
        #expect(BatteryCSV.daily(restored).contains("Replaced adapter"))
    }
    @Test @MainActor func testStoreMigratesHistoryAndPersistsNotesAcrossRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "BatteryScopeTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var r = BatteryReading(); r.fullMAh = 3600; r.designMAh = 4000
        try JSONEncoder().encode([r]).write(to: folder.appendingPathComponent("history.json"))
        let store = BatteryStore(directory: folder, defaults: defaults, startMonitoring: false)
        #expect(store.dailyHistory.count == 1)
        let day = store.dailyHistory[0].id
        store.updateNote(day: day, note: "A useful note")
        store.settings.healthSource = .nominal
        let restored = BatteryStore(directory: folder, defaults: defaults, startMonitoring: false)
        #expect(restored.dailyHistory[0].note == "A useful note")
        #expect(restored.settings.healthSource == .nominal)
        #expect(restored.history.count == 1)
    }
    @Test @MainActor func testCorruptHistoryIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("history.json")
        let original = Data("damaged but recoverable".utf8)
        try original.write(to: path)
        let suite = "BatteryScopeTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BatteryStore(directory: folder, defaults: defaults, startMonitoring: false)
        #expect(store.error != nil)
        store.record(BatteryReading())
        #expect(try Data(contentsOf: path) == original)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BATTERYSCOPE_LIVE_TEST"] == "1")) func testOptionalLiveBattery() throws {
        let r = try BatteryReader.read()
        #expect(r.registrySource != nil)
        #expect(r.percent != nil)
        #expect(r.cycles != nil)
        #expect(r.macOSHealth == nil)
    }
}
