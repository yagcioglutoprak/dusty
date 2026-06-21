import Foundation

public struct ParsedArgs: Equatable {
    public var command: String
    public var level: String?
    public var json = false
    public var yes = false
    public var dryRun = false
    public var trash = false
}

public func parseArgs(_ args: [String]) -> ParsedArgs? {
    guard let command = args.first, !command.hasPrefix("-") || command == "--version" else { return nil }
    var parsed = ParsedArgs(command: command == "--version" ? "version" : command)
    var rest = args.dropFirst()
    while let arg = rest.first {
        rest = rest.dropFirst()
        switch arg {
        case "--level", "-l":
            guard let value = rest.first, !value.hasPrefix("-") else { return nil }
            rest = rest.dropFirst()
            parsed.level = value
        case "--json": parsed.json = true
        case "--yes", "-y": parsed.yes = true
        case "--dry-run", "-n": parsed.dryRun = true
        case "--trash", "-t": parsed.trash = true
        default: return nil
        }
    }
    return parsed
}

public func levels(from name: String?, defaultAll: Bool) -> Set<CleanupLevel>? {
    switch (name ?? (defaultAll ? "all" : "safe")).lowercased() {
    case "all": return Set(CleanupLevel.allCases)
    case "safe", "1": return [.safe]
    case "developer", "dev", "2": return [.developer]
    case "deep", "3": return [.deep]
    default: return nil
    }
}
