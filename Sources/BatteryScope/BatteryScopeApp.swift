import SwiftUI
import BatteryCore
import UserNotifications
import Charts
import AppKit
import UniformTypeIdentifiers

let mint = Color(red: 0.53, green: 0.93, blue: 0.72)
let muted = Color(red: 0.57, green: 0.62, blue: 0.63)
let panel = Color(red: 0.075, green: 0.10, blue: 0.105)
let appBackground = Color(red: 0.045, green: 0.065, blue: 0.07)

@main struct BatteryScopeApp: App {
    @StateObject private var store = BatteryStore()
    init() {
        if CommandLine.arguments.contains("--diagnostics") {
            do {
                var reading = try BatteryReader.read()
                // Diagnostics is an explicit one-shot read; it writes no history or settings.
                reading.macOSHealth = nil
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(data: try encoder.encode(reading), encoding: .utf8)!)
                exit(0)
            } catch { fputs("BatteryScope: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        UNUserNotificationCenter.current().delegate = ForegroundNotifications.shared
    }
    var body: some Scene {
        WindowGroup("BatteryScope", id: "dashboard") {
            Dashboard(store: store).preferredColorScheme(.dark)
        }
        .defaultSize(width: 1120, height: 790)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(systemName: store.reading?.charging == true ? "battery.100percent.bolt" : "battery.75percent")
            Text(store.reading?.percent.map { "\(Int($0))%" } ?? "—")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var store: BatteryStore
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text("BatteryScope")
        if let r = store.reading {
            Text("\(r.state) · \(r.percent.map { String(format: "%.0f%%", $0) } ?? "—")")
            Text(r.full ? "Fully charged" : r.pluggedIn && !r.charging ? "Connected · not charging" : "\(durationText(r.estimate.0)) · \(r.charging ? "to full" : "remaining")")
            Text("Health \(format(r.health(from: store.settings.healthSource), "%.1f%%")) · \(r.cycles.map(String.init) ?? "—") cycles")
        }
        Divider()
        Button("Open dashboard") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
        Button("Refresh") { store.refresh() }
        Divider()
        Button("Quit BatteryScope") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

func format(_ value: Double?, _ pattern: String) -> String {
    value.map { String(format: pattern, $0) } ?? "—"
}

@MainActor final class DashboardState: ObservableObject {
    @Published var section = "Overview"
    @Published var range = "24 hours"
    @Published var exportError: String?
}

struct Dashboard: View {
    @ObservedObject var store: BatteryStore
    @StateObject var ui = DashboardState()
    var r: BatteryReading? { store.reading }
    private var chartData: [BatteryReading] {
        let seconds: Double = ui.range == "1 hour" ? 3600 : ui.range == "24 hours" ? 86400 : 7 * 86400
        return store.history.filter { $0.date > Date().addingTimeInterval(-seconds) }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let error = store.error { Text(error).font(.callout).foregroundStyle(.orange).padding().frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 12)) }
                    if ui.section == "Overview" { overview }
                    else if ui.section == "History" { historyContent }
                    else if ui.section == "Battery details" { details }
                    else if ui.section == "Sources & power" { sourcesContent }
                    else if ui.section == "Lifetime" { lifetimeContent }
                    else { settings }
                    HStack {
                        Circle().fill(r == nil ? .orange : mint).frame(width: 5, height: 5)
                        Text(r.map { "Updated \($0.date.formatted(date: .omitted, time: .standard)) · refreshes every \(Int(store.settings.refreshSeconds)) seconds" } ?? "Waiting for battery")
                        Spacer()
                        Text("ON-DEVICE ONLY").tracking(1.5)
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
                }.padding(32)
            }.background(appBackground)
        }
        .frame(minWidth: 960, minHeight: 700)
        .tint(mint)
        .alert("Export failed", isPresented: Binding(get: { ui.exportError != nil }, set: { if !$0 { ui.exportError = nil } })) { Button("OK") { ui.exportError = nil } } message: { Text(ui.exportError ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path").foregroundStyle(mint).font(.system(size: 25, weight: .medium))
                Text("BatteryScope").font(.system(size: 18, weight: .semibold))
            }.padding(.top, 40).padding(.bottom, 8)
            Text("KNOW YOUR POWER").font(.system(size: 9, weight: .medium)).tracking(2.2).foregroundStyle(muted).padding(.leading, 35)
            VStack(spacing: 6) {
                nav("Overview", "square.grid.2x2")
                nav("History", "chart.xyaxis.line")
                nav("Battery details", "battery.100percent")
                nav("Sources & power", "point.3.connected.trianglepath.dotted")
                nav("Lifetime", "clock.arrow.circlepath")
                nav("Preferences", "slider.horizontal.3")
            }.padding(.top, 44)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack { Image(systemName: "laptopcomputer"); Text("This Mac").fontWeight(.medium) }.foregroundStyle(.white)
                Text(ProcessInfo.processInfo.operatingSystemVersionString).font(.system(size: 10)).foregroundStyle(muted)
                Text("Native battery monitor · v0.2").font(.system(size: 10)).foregroundStyle(muted)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 12))
        }.padding(.horizontal, 18).padding(.bottom, 24).frame(width: 220).background(Color(red: 0.055, green: 0.08, blue: 0.085))
    }
    func nav(_ title: String, _ icon: String) -> some View {
        Button { ui.section = title } label: {
            HStack(spacing: 12) { Image(systemName: icon).frame(width: 18); Text(title); Spacer() }
                .font(.system(size: 12, weight: .medium)).padding(12)
                .foregroundStyle(ui.section == title ? mint : muted)
                .background(ui.section == title ? mint.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("YOUR MAC, AT A GLANCE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(mint)
                Text(ui.section).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(ui.section == "Overview" ? "A little clarity for every charge." : "A closer look at your battery.").font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer()
            Button { exportCSV() } label: { Label("Export data", systemImage: "arrow.down.to.line").font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6) }.buttonStyle(.bordered)
        }
    }
    var overview: some View {
        VStack(spacing: 18) {
            if let r, !r.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Battery needs attention", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    ForEach(r.warnings, id: \.self) { Text($0).font(.system(size: 12)) }
                    Text("Device-reported status. Review Battery settings for service guidance.").font(.system(size: 10))
                }.foregroundStyle(.orange).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(spacing: 24) {
                ZStack {
                    Circle().stroke(mint.opacity(0.08), lineWidth: 13)
                    Circle().trim(from: 0, to: (r?.percent ?? 0) / 100).stroke(mint, style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Image(systemName: r?.charging == true ? "bolt.fill" : "battery.75percent").foregroundStyle(mint).font(.system(size: 18))
                        Text(format(r?.percent, "%.0f%%")).font(.system(size: 39, weight: .medium, design: .rounded))
                        Text("CURRENT CHARGE").font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(muted)
                    }
                }.frame(width: 164, height: 164).padding(8)
                VStack(alignment: .leading, spacing: 13) {
                    Label(r?.state ?? "Battery unavailable", systemImage: r?.charging == true ? "bolt.circle.fill" : "circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(mint)
                    Text(r?.full == true ? "100% charged" : r?.pluggedIn == true && r?.charging == false ? "Not charging" : durationText(r?.estimate.0)).font(.system(size: 38, weight: .medium, design: .rounded))
                    Text(r?.estimate.1 ?? "Connect a Mac battery to get started").font(.system(size: 11)).foregroundStyle(muted)
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                    Text(r?.charging == true ? "Charge speed tapers near full. Actual time may vary." : "Remaining time changes with your workload.").font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
            }.padding(24).frame(maxWidth: .infinity).background(panel, in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 12) {
                metric("Battery health", value: format(r?.health(from: store.settings.healthSource), "%.1f%%"), note: store.settings.healthSource.title, icon: "heart", color: mint)
                metric("Cycle count", value: r?.cycles.map(String.init) ?? "—", note: "Full equivalent charge cycles", icon: "arrow.triangle.2.circlepath", color: .cyan)
                metric("Temperature", value: format(r?.temperature(from: store.settings.temperatureSource), "%.1f° C"), note: store.settings.temperatureSource.title, icon: "thermometer.medium", color: .orange)
            }
            chargeChart
            HStack(spacing: 12) {
                metric("Battery power", value: format(r?.power(from: store.settings.currentSource).map(abs), "%.1f W"), note: store.settings.currentSource.title + " · net battery flow", icon: "bolt", color: mint)
                metric("Power adapter", value: format(r?.adapterWatts, "%.0f W"), note: r?.pluggedIn == true ? "Connected · rated output" : "Last reported adapter rating", icon: "powerplug", color: .cyan)
                metric("System load", value: format(r?.systemWatts, "%.1f W"), note: "Reported system telemetry", icon: "cpu", color: .purple)
            }
        }
    }
    func metric(_ title: String, value: String, note: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.system(size: 11)).foregroundStyle(muted); Spacer(); Image(systemName: icon).foregroundStyle(color).font(.system(size: 12)) }
            Text(value).font(.system(size: 25, weight: .medium, design: .rounded))
            Text(note).font(.system(size: 9)).foregroundStyle(muted).lineLimit(2)
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 13))
    }
    var chargeChart: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("Charge history").font(.system(size: 13, weight: .semibold)); Text("Real samples, saved every minute while BatteryScope is running").font(.system(size: 10)).foregroundStyle(muted) }
                Spacer()
                Picker("Range", selection: $ui.range) { Text("1 hour").tag("1 hour"); Text("24 hours").tag("24 hours"); Text("7 days").tag("7 days") }.labelsHidden().frame(width: 110)
            }
            if chartData.count < 2 {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 24)).foregroundStyle(mint)
                    Text("Your history starts here").font(.system(size: 12, weight: .medium))
                    Text("Keep BatteryScope open. The first chart appears after two samples.").font(.system(size: 10)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity).frame(height: 130)
            } else {
                Chart(chartData) { item in
                    if let percent = item.percent {
                        AreaMark(x: .value("Time", item.date), y: .value("Charge", percent)).foregroundStyle(LinearGradient(colors: [mint.opacity(0.18), mint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Time", item.date), y: .value("Charge", percent)).foregroundStyle(mint).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Time", item.date), y: .value("Charge", percent)).foregroundStyle(mint).symbolSize(chartData.count < 10 ? 20 : 0)
                    }
                }.chartYScale(domain: 0...100).chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(.white.opacity(0.05)); AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%").font(.system(size: 9)).foregroundStyle(muted) } } } }.frame(height: 145)
            }
        }.padding(20).background(panel, in: RoundedRectangle(cornerRadius: 16))
    }
    var historyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            chargeChart
            HStack(spacing: 12) {
                metric("Saved readings", value: "\(store.history.count)", note: "Up to 14 days retained locally", icon: "externaldrive", color: mint)
                metric("Health change", value: healthChange, note: "Since first daily snapshot · selected source", icon: "heart.text.clipboard", color: .cyan)
            }
            dailyHistoryContent
            Text("Recent readings").font(.headline)
            HStack { Text("TIME"); Spacer(); Text("CHARGE").frame(width: 75); Text("HEALTH").frame(width: 75); Text("STATE").frame(width: 150) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(muted)
            ForEach(Array(store.history.suffix(30).reversed())) { item in
                HStack { Text(item.date.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(format(item.percent, "%.0f%%")).frame(width: 75); Text(format(item.health(from: store.settings.healthSource), "%.1f%%")).frame(width: 75); Text(item.state).frame(width: 150) }.font(.system(size: 11)).padding(.vertical, 8)
                Divider().opacity(0.3)
            }
        }
    }
    var healthChange: String {
        guard let a = store.dailyHistory.first?.reading.health(from: store.settings.healthSource), let b = store.dailyHistory.last?.reading.health(from: store.settings.healthSource), store.dailyHistory.count > 1 else { return "Collecting…" }
        return String(format: "%+.2f pts", b-a)
    }
    var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Battery telemetry").font(.headline)
            VStack(spacing: 0) {
                detail("Condition reported by macOS", r?.condition ?? "Unavailable")
                detail("Full capacity (raw)", r?.capacityText(r?.rawFullMAh, unit: store.settings.capacityUnit) ?? "—")
                detail("Full capacity (nominal)", r?.capacityText(r?.nominalFullMAh ?? r?.fullMAh, unit: store.settings.capacityUnit) ?? "—")
                detail("Original design capacity", r?.capacityText(r?.designMAh, unit: store.settings.capacityUnit) ?? "—")
                detail("Remaining raw capacity", r?.capacityText(r?.remainingMAh, unit: store.settings.capacityUnit) ?? "—")
                detail("Health · raw capacity", format(r?.health(from: .raw), "%.1f%%"))
                detail("Health · nominal capacity", format(r?.health(from: .nominal), "%.1f%%"))
                detail("Health · macOS reported", format(r?.macOSHealth, "%.0f%%"))
                detail("Cycle count", r?.cycles.map(String.init) ?? "—")
                detail("Voltage", format(r?.volts, "%.3f V"))
                detail("Current (+ charge / − discharge)", format(r?.amps, "%+.3f A"))
                detail("Battery sensor temperature", format(r?.temperatureC, "%.1f °C"))
                detail("Virtual temperature", format(r?.virtualTemperatureC, "%.1f °C"))
                detail("Low Power Mode", r?.lowPowerMode.map { $0 ? "Enabled" : "Disabled" } ?? "Unavailable")
                detail("Permanent fault status", r?.faultStatus.map { String(format: "0x%llX", $0) } ?? "Unavailable")
                detail("Not-charging reason (raw firmware code)", r?.notChargingReason.map { String($0) } ?? "Unavailable")
                detail("Lifetime minimum temperature (firmware)", format(r?.lifetimeMinC, "%.1f °C"))
                detail("Lifetime average temperature (firmware)", format(r?.lifetimeAverageC, "%.1f °C"))
                detail("Lifetime maximum temperature (firmware)", format(r?.lifetimeMaxC, "%.1f °C"))
                detail("External power connected", r.map { $0.pluggedIn ? "Yes" : "No" } ?? "—")
            }.padding(.horizontal, 20).background(panel, in: RoundedRectangle(cornerRadius: 14))
            Text("How to read these numbers").font(.headline)
            Text("Raw and nominal health each divide their own full capacity by design capacity. macOS health is a separate reported percentage. These can differ. Wh values approximate energy using the current pack voltage. Capacity varies with temperature and the battery's own calibration. A cycle represents a cumulative 100% of battery use, across any number of sessions. Time estimates come from macOS and may be unavailable during charging pauses or changing workloads.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(6)
            Text("Source: local IOKit power sources and AppleSmartBattery registry. No serial numbers are collected. Sensor fields vary between Mac models.").font(.system(size: 11)).foregroundStyle(muted)
        }
    }
    func detail(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) { HStack { Text(title).foregroundStyle(muted); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 12)).padding(.vertical, 15); Divider().opacity(0.25) }
    }
    var settings: some View { preferencesContent }
    func exportCSV() {
        let save = NSSavePanel()
        save.allowedContentTypes = [.commaSeparatedText]
        save.nameFieldStringValue = "BatteryScope-history.csv"
        guard save.runModal() == .OK, let url = save.url else { return }
        let csv = BatteryCSV.readings(store.history)
        do { try csv.write(to: url, atomically: true, encoding: .utf8) } catch { ui.exportError = error.localizedDescription }
    }
}

final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotifications()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
