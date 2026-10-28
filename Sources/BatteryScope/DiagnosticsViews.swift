import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers
import BatteryCore

extension Dashboard {
    var sourcesContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose a source. Keep the differences visible.").font(.headline)
            sourcePickers
            HStack(spacing: 12) {
                ForEach(HealthSource.allCases) { source in
                    metric(source.title, value: format(r?.health(from: source), "%.2f%%"), note: source == .macOS ? "pmset · cached up to 30 minutes" : "Full capacity ÷ design capacity", icon: "heart", color: source == .raw ? mint : source == .nominal ? .cyan : .orange)
                }
            }
            VStack(spacing: 0) {
                detail("System charge percentage", format(r?.percent, "%.1f%%"))
                detail("Raw charge percentage", format(r?.rawPercent, "%.1f%%"))
                detail("Reported current · Amperage", format(r?.amps, "%+.3f A"))
                detail("Instantaneous current · InstantAmperage", format(r?.instantAmps, "%+.3f A"))
                detail("Battery flow · reported current × voltage", format(r?.power(from: .reported), "%+.2f W"))
                detail("Battery flow · instantaneous current × voltage", format(r?.power(from: .instantaneous), "%+.2f W"))
                detail("System load · registry telemetry", format(r?.systemWatts, "%.2f W"))
                detail("System input · registry telemetry", format(r?.inputWatts, "%.2f W"))
                detail("Adapter rated output", format(r?.adapterWatts, "%.0f W"))
                detail("Sensor · Temperature / 100", format(r?.temperatureC, "%.2f °C"))
                detail("Virtual · VirtualTemperature / 100", format(r?.virtualTemperatureC, "%.2f °C"))
                detail("Registry service", r?.registrySource ?? "Unavailable")
                detail("macOS health sampled", r?.macOSHealthDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable")
            }.padding(.horizontal, 20).background(panel, in: RoundedRectangle(cornerRadius: 14))
            Text("Sources describe different measurements. A missing selected source stays unavailable. Battery flow is signed: positive means charging; negative means discharging. Adapter rating and system input are separate from battery power. Wall-energy counters are not presented as watts.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
        }
    }
    var sourcePickers: some View {
        VStack(spacing: 14) {
            Picker("Health shown on dashboard", selection: $store.settings.healthSource) { ForEach(HealthSource.allCases) { Text($0.title).tag($0) } }
            Picker("Temperature shown on dashboard", selection: $store.settings.temperatureSource) { ForEach(TemperatureSource.allCases) { Text($0.title).tag($0) } }
            Picker("Battery power source", selection: $store.settings.currentSource) { ForEach(CurrentSource.allCases) { Text($0.title).tag($0) } }
            Picker("Capacity units", selection: $store.settings.capacityUnit) { ForEach(CapacityUnit.allCases) { Text($0.rawValue).tag($0) } }
        }.font(.system(size: 12)).padding(20).background(panel, in: RoundedRectangle(cornerRadius: 14))
    }
    var lifetimeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recorded by your battery's firmware").font(.headline)
            Text("These records can predate BatteryScope. Availability and counter units depend on the Mac and battery firmware.").font(.system(size: 12)).foregroundStyle(muted)
            VStack(spacing: 0) {
                detail("Minimum temperature", format(r?.lifetimeMinC, "%.1f °C"))
                detail("Average temperature", format(r?.lifetimeAverageC, "%.1f °C"))
                detail("Maximum temperature", format(r?.lifetimeMaxC, "%.1f °C"))
                detail("Minimum pack voltage", format(r?.lifetimeMinVolts, "%.3f V"))
                detail("Maximum pack voltage", format(r?.lifetimeMaxVolts, "%.3f V"))
                detail("Maximum charge current · magnitude", format(r?.lifetimeMaxChargeAmps, "%.3f A"))
                detail("Maximum discharge current · magnitude", format(r?.lifetimeMaxDischargeAmps, "%.3f A"))
                detail("Operating-time counter · raw units", format(r?.operatingTimeCounter, "%.0f"))
                detail("Temperature samples · firmware count", format(r?.temperatureSampleCount, "%.0f"))
                detail("Charge cycles", r?.cycles.map(String.init) ?? "Unavailable")
            }.padding(.horizontal, 20).background(panel, in: RoundedRectangle(cornerRadius: 14))
            Text("Current and voltage use the reported mA/mV scale. Lifetime temperatures use the observed tenths-of-a-degree scale. Firmware counters are kept in raw units where a reliable duration conversion is unavailable; BatteryScope does not invent an operating age or recording period.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(5)
        }
    }
    var preferencesContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sourcePickers
            VStack(alignment: .leading, spacing: 14) {
                Picker("Refresh interval", selection: $store.settings.refreshSeconds) {
                    ForEach([5.0, 10, 30, 60], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                Text("Power changes and wake events trigger extra refreshes. History is saved at most once a minute.").font(.system(size: 11)).foregroundStyle(muted)
            }.padding(20).background(panel, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Battery notifications", isOn: Binding(get: { store.settings.alertsEnabled }, set: { store.configureAlerts($0) })).font(.headline)
                Stepper("Low battery: \(store.settings.lowPercent)%", value: $store.settings.lowPercent, in: 1...50)
                Stepper("Charge target: \(store.settings.chargedPercent)%", value: $store.settings.chargedPercent, in: 50...100)
                Toggle("Notify on estimated time remaining", isOn: $store.settings.timeAlertEnabled)
                Stepper("Remaining time: \(store.settings.remainingMinutes) minutes", value: $store.settings.remainingMinutes, in: 5...120, step: 5)
                Text(store.alertStatus).font(.system(size: 11)).foregroundStyle(muted)
                Text("Each alert fires once when its threshold is crossed and rearms after recovery. Charge targets notify you; they do not stop charging.").font(.system(size: 11)).foregroundStyle(muted)
            }.padding(20).background(panel, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 12) {
                Text("Private by design").font(.headline)
                Text("Recent minute samples: 14 days. Daily health snapshots and notes: up to five years. All data stays in Application Support/BatteryScope. Sampling stops when you quit.").font(.system(size: 12)).foregroundStyle(muted)
                Button("Show history in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.historyURL]) }
            }.padding(20).background(panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }
    var dailyHistoryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Long-term battery health").font(.headline)
                    Text("Daily snapshots · \(store.dailyHistory.count) days · three independent sources").font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer()
                Button("Export daily CSV") { exportDaily() }
            }
            if store.dailyHistory.count > 1 {
                Chart {
                    ForEach(HealthSource.allCases) { source in
                        ForEach(store.dailyHistory) { day in
                            if let value = day.reading.health(from: source) {
                                LineMark(x: .value("Day", day.reading.date), y: .value("Health", value), series: .value("Source", source.title)).foregroundStyle(by: .value("Source", source.title))
                                PointMark(x: .value("Day", day.reading.date), y: .value("Health", value)).foregroundStyle(by: .value("Source", source.title)).symbolSize(12)
                            }
                        }
                    }
                }.chartForegroundStyleScale(["Raw capacity": mint, "Nominal capacity": Color.cyan, "macOS reported": Color.orange]).frame(height: 170)
            } else {
                Text("The health trend appears after two daily snapshots. Existing recent history is migrated automatically.").font(.system(size: 12)).foregroundStyle(muted).padding(.vertical, 20)
            }
            ForEach(Array(store.dailyHistory.suffix(14).reversed())) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(day.id).fontWeight(.medium); Spacer(); Text(format(day.reading.health(from: store.settings.healthSource), "%.1f%%")); Text("\(day.reading.cycles.map(String.init) ?? "—") cycles").foregroundStyle(muted) }.font(.system(size: 11))
                    TextField("Add a note for this day…", text: Binding(get: { store.dailyHistory.first(where: { $0.id == day.id })?.note ?? "" }, set: { store.updateNote(day: day.id, note: $0) })).textFieldStyle(.roundedBorder).font(.system(size: 11))
                }
            }
        }.padding(20).background(panel, in: RoundedRectangle(cornerRadius: 14))
    }
    func exportDaily() {
        let save = NSSavePanel()
        save.allowedContentTypes = [.commaSeparatedText]
        save.nameFieldStringValue = "BatteryScope-daily-health.csv"
        guard save.runModal() == .OK, let url = save.url else { return }
        do { try BatteryCSV.daily(store.dailyHistory).write(to: url, atomically: true, encoding: .utf8) }
        catch { ui.exportError = error.localizedDescription }
    }
}
