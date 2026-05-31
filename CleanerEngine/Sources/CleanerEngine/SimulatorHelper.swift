import Foundation

enum SimulatorHelper {
    /// UDIDs of simulators currently booted.
    static func bootedDeviceUDIDs(fileManager: FileManager = .default) -> Set<String> {
        guard let output = runSimctl(arguments: ["list", "devices", "booted"]) else { return [] }
        return parseUDIDs(from: output)
    }

    /// Device folder paths for shutdown simulators (excludes booted).
    static func unusedDevicePaths(basePath: String, fileManager: FileManager = .default) -> [(path: String, name: String)] {
        let booted = bootedDeviceUDIDs(fileManager: fileManager)
        guard let uuids = try? fileManager.contentsOfDirectory(atPath: basePath) else { return [] }

        var nameByUDID: [String: String] = [:]
        if let json = runSimctl(arguments: ["list", "devices", "-j"]),
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let devices = parsed["devices"] as? [String: Any] {
            for (_, runtimeDevices) in devices {
                guard let list = runtimeDevices as? [[String: Any]] else { continue }
                for device in list {
                    if let udid = device["udid"] as? String,
                       let name = device["name"] as? String {
                        nameByUDID[udid] = name
                    }
                }
            }
        }

        return uuids.compactMap { udid -> (String, String)? in
            guard udid.count >= 32, !booted.contains(udid) else { return nil }
            let path = (basePath as NSString).appendingPathComponent(udid)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let name = nameByUDID[udid] ?? udid
            return (path, "\(name) (\(udid.prefix(8))…)")
        }
    }

    static func unavailableDeviceUDIDs() -> [String] {
        guard let output = runSimctl(arguments: ["list", "devices", "unavailable"]) else { return [] }
        return Array(parseUDIDs(from: output))
    }

    static func unavailableDeviceCount() -> Int {
        unavailableDeviceUDIDs().count
    }

    private static func runSimctl(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func parseUDIDs(from output: String) -> Set<String> {
        let pattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(output.startIndex..., in: output)
        return Set(regex.matches(in: output, range: range).compactMap { match in
            guard let r = Range(match.range, in: output) else { return nil }
            return String(output[r])
        })
    }
}
