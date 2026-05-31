import Foundation

public protocol DeletionLogStore: Sendable {
    func append(_ entry: DeletionEntry) throws
    func loadAll() throws -> [DeletionEntry]
    var logFileURL: URL { get }
}

public final class FileDeletionLogStore: DeletionLogStore, @unchecked Sendable {
    public let logFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "sh.toprak.dusty.deletion-log")

    public init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dusty", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("deletion-log.jsonl")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ entry: DeletionEntry) throws {
        try queue.sync {
            let data = try encoder.encode(entry)
            var line = data
            line.append(Data([0x0A]))
            if fileManager.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: logFileURL)
            }
            rotateIfNeeded()
        }
    }

    /// Trim to the most recent half once the log passes ~1 MB.
    private func rotateIfNeeded() {
        guard let size = (try? fileManager.attributesOfItem(atPath: logFileURL.path))?[.size] as? Int,
              size > 1_000_000,
              let text = try? String(contentsOf: logFileURL, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let kept = lines.suffix(lines.count / 2).joined(separator: "\n") + "\n"
        try? kept.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    public func loadAll() throws -> [DeletionEntry] {
        try queue.sync {
            guard fileManager.fileExists(atPath: logFileURL.path) else { return [] }
            let data = try Data(contentsOf: logFileURL)
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { line in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(DeletionEntry.self, from: d)
            }
        }
    }

    private var fileManager: FileManager { .default }
}
