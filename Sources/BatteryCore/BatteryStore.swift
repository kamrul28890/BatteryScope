import Foundation
import Combine
import UserNotifications
import AppKit
import IOKit.ps

@MainActor public final class BatteryStore: ObservableObject {
    @Published public var reading: BatteryReading?
    @Published public var history: [BatteryReading] = []
    @Published public var dailyHistory: [DailySnapshot] = []
    @Published public var error: String?
    @Published public var alertStatus = "Alerts are off"
    @Published public var settings: BatterySettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings.v2") }
            if settings.refreshSeconds != oldValue.refreshSeconds { startTimer() }
            if settings != oldValue { activeAlerts = [] }
        }
    }
    private let defaults: UserDefaults
    private let directory: URL
    private var persistenceAvailable = true
    private var timer: Timer?
    private var lastSaved = Date.distantPast
    private var activeAlerts: Set<BatteryAlert> = []
    private var healthQueryDate = Date.distantPast
    private var cachedHealth: Double?
    private var cachedHealthDate: Date?
    private var healthQueryRunning = false
    private var powerSource: CFRunLoopSource?
    private var wakeToken: NSObjectProtocol?
    public var historyURL: URL { directory.appendingPathComponent("history.json") }
    public var dailyURL: URL { directory.appendingPathComponent("daily-health.json") }

    public init(directory: URL? = nil, defaults: UserDefaults = .standard, startMonitoring: Bool = true) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BatteryScope")
        if let data = defaults.data(forKey: "settings.v2"), let saved = try? JSONDecoder().decode(BatterySettings.self, from: data) { settings = saved }
        else { settings = BatterySettings() }
        settings.refreshSeconds = [5.0, 10, 30, 60].contains(settings.refreshSeconds) ? settings.refreshSeconds : 10
        settings.lowPercent = min(50, max(1, settings.lowPercent))
        settings.chargedPercent = min(100, max(50, settings.chargedPercent))
        settings.remainingMinutes = min(120, max(5, settings.remainingMinutes))
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: historyURL.path) { history = try JSONDecoder().decode([BatteryReading].self, from: Data(contentsOf: historyURL)) }
            if FileManager.default.fileExists(atPath: dailyURL.path) { dailyHistory = try JSONDecoder().decode([DailySnapshot].self, from: Data(contentsOf: dailyURL)) }
            else { for item in history { DailySnapshot.record(item, in: &dailyHistory) } }
        } catch { persistenceAvailable = false; self.error = "Could not load history; existing files were left untouched: \(error.localizedDescription)" }
        if startMonitoring {
            refresh()
            startTimer()
            installPowerObservers()
            if settings.alertsEnabled { checkNotificationPermission() }
        }
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshSeconds, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    private func installPowerObservers() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<BatteryStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.refresh() }
        }, context)?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    deinit {
        timer?.invalidate()
        if let source = powerSource { CFRunLoopSourceInvalidate(source) }
        if let token = wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
    public func refresh() {
        do {
            var value = try BatteryReader.read()
            value.macOSHealth = cachedHealth
            value.macOSHealthDate = cachedHealthDate
            reading = value
            record(value)
            checkAlerts(value)
            if !healthQueryRunning && Date().timeIntervalSince(healthQueryDate) >= 1800 {
                healthQueryRunning = true
                healthQueryDate = Date()
                Task { [weak self] in
                    let value = await MacOSHealthReader.read()
                    guard let self else { return }
                    self.cachedHealth = value
                    self.cachedHealthDate = value == nil ? nil : Date()
                    self.healthQueryRunning = false
                    self.reading?.macOSHealth = value
                    self.reading?.macOSHealthDate = self.cachedHealthDate
                }
            }
        } catch { self.error = error.localizedDescription; reading = nil }
    }
    public func record(_ value: BatteryReading) {
        guard persistenceAvailable, value.date.timeIntervalSince(lastSaved) >= 60 else { return }
        history.append(value)
        let cutoff = value.date.addingTimeInterval(-14 * 86400)
        history.removeAll { $0.date < cutoff }
        if history.count > 21000 { history = Array(history.suffix(21000)) }
        DailySnapshot.record(value, in: &dailyHistory)
        do {
            try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
            try JSONEncoder().encode(dailyHistory).write(to: dailyURL, options: .atomic)
            lastSaved = value.date
        } catch { self.error = "History could not be saved: \(error.localizedDescription)" }
    }
    public func updateNote(day: String, note: String) {
        guard persistenceAvailable, let index = dailyHistory.firstIndex(where: { $0.id == day }) else { return }
        dailyHistory[index].note = note
        do { try JSONEncoder().encode(dailyHistory).write(to: dailyURL, options: .atomic) }
        catch { self.error = "Note could not be saved: \(error.localizedDescription)" }
    }
    public func configureAlerts(_ enabled: Bool) {
        settings.alertsEnabled = enabled
        activeAlerts = []
        guard enabled else { alertStatus = "Alerts are off"; return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in self?.alertStatus = error?.localizedDescription ?? (granted ? "Battery alerts enabled" : "Allow notifications in System Settings") }
        }
    }
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in self?.alertStatus = settings.authorizationStatus == .authorized ? "Battery alerts enabled" : "Allow notifications in System Settings" }
        }
    }
    private func checkAlerts(_ r: BatteryReading) {
        let active = BatteryAlert.active(reading: r, settings: settings)
        defer { activeAlerts = active }
        for alert in active.subtracting(activeAlerts) {
            let content = UNMutableNotificationContent()
            switch alert {
            case .low: content.title = "Battery is running low"; content.body = "Charge is at or below \(settings.lowPercent)%."
            case .charged: content.title = "Charge target reached"; content.body = "Your battery has reached \(settings.chargedPercent)%."
            case .time: content.title = "Battery time is running low"; content.body = "macOS estimates \(durationText(r.minutesToEmpty)) remaining."
            }
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "battery-\(alert.rawValue)", content: content, trigger: nil)) { [weak self] error in
                if let error { Task { @MainActor in self?.alertStatus = "Notification failed: \(error.localizedDescription)" } }
            }
        }
    }
}
