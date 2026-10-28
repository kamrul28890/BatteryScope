import Foundation
import IOKit
import IOKit.ps

public enum BatteryReader {
    public struct Snapshot {
        public var properties: [String: Any]
        public var source: String
    }
    /// Merge battery-pack fields over the older service without persisting raw dictionaries.
    public static func normalize(root: [String: Any], pack: [String: Any]?) -> Snapshot {
        guard let pack else { return Snapshot(properties: root, source: "AppleSmartBattery") }
        var merged = root
        if let children = pack["EntryChildren"] as? [String: Any], let data = children["BatteryData"] as? [String: Any] {
            merged.merge(data) { _, new in new }
        }
        if let data = pack["BatteryData"] as? [String: Any] { merged.merge(data) { _, new in new } }
        merged.merge(pack) { _, new in new }
        return Snapshot(properties: merged, source: "AppleSmartBatteryPack + AppleSmartBattery")
    }
    private static func properties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var raw: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return raw?.takeRetainedValue() as? [String: Any]
    }
    public static func read() throws -> BatteryReading {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        let pack = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryPack"))
        defer { if entry != 0 { IOObjectRelease(entry) }; if pack != 0 { IOObjectRelease(pack) } }
        let parent = entry != 0 ? properties(entry) : nil
        var child = pack != 0 ? properties(pack) : nil
        // Some OS versions expose the pack as a named child rather than a matching class.
        if child == nil, entry != 0 {
            var iterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                while true {
                    let item = IOIteratorNext(iterator)
                    if item == 0 { break }
                    defer { IOObjectRelease(item) }
                    var name = [CChar](repeating: 0, count: 128)
                    if IORegistryEntryGetName(item, &name) == KERN_SUCCESS, String(cString: name) == "AppleSmartBatteryPack" {
                        child = properties(item); break
                    }
                }
            }
        }
        guard parent != nil || child != nil else { throw ReaderError.noBattery }
        let snapshot = normalize(root: parent ?? [:], pack: child)
        var source: [String: Any] = [:]
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for item in list {
                if let d = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any], d["Type"] as? String == "InternalBattery" { source = d; break }
            }
        }
        var reading = BatteryReading.decode(snapshot.properties, powerSource: source, remainingSeconds: IOPSGetTimeRemainingEstimate(), sourceName: snapshot.source)
        reading.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        return reading
    }
    public enum ReaderError: LocalizedError {
        case noBattery
        public var errorDescription: String? { "No readable internal battery was found. BatteryScope requires a Mac notebook." }
    }
}

public enum MacOSHealthReader {
    /// Public command output only. No private powerlog database or elevated access.
    public static func parse(_ data: Data) -> Double? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        func find(_ object: Any) -> Double? {
            if let dict = object as? [String: Any] {
                for key in ["Maximum Capacity Percent", "MaximumCapacityPercent", "MaxCapacityPercent"] {
                    if let n = dict[key] as? NSNumber, (0...100).contains(n.doubleValue) { return n.doubleValue }
                }
                for key in ["BatteryPacks", "BatteryData", "InternalBattery"] {
                    if let value = dict[key], let n = find(value) { return n }
                }
            }
            if let array = object as? [Any] { for item in array { if let n = find(item) { return n } } }
            return nil
        }
        return find(plist)
    }
    public static func read() async -> Double? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "ps", "-xml"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: timeout)
            let data = pipe.fileHandleForReading.readData(ofLength: 1_048_576)
            if data.count == 1_048_576, process.isRunning { process.terminate() }
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0, data.count < 1_048_576 else { return nil }
            return parse(data)
        }.value
    }
}
