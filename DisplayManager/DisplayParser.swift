import Foundation

enum DisplayMode {
    case mirrored
    case extended
    case unknown
}

struct DisplayInfo: Equatable {
    let id: String
    let config: String
}

enum DisplayParser {
    /// Parses a full `displayplacer list` output into the per-display configs
    /// found on the `displayplacer "..." "..."` command line.
    static func parseDisplays(_ output: String) -> [DisplayInfo] {
        guard let cmdLine = output
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("displayplacer \"") }) else {
            return []
        }
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"") else {
            return []
        }
        let nsString = cmdLine as NSString
        let matches = regex.matches(
            in: cmdLine,
            range: NSRange(location: 0, length: nsString.length)
        )
        return matches.compactMap { match -> DisplayInfo? in
            guard match.numberOfRanges > 1 else { return nil }
            let config = nsString.substring(with: match.range(at: 1))
            guard let idRange = config.range(
                of: "id:([A-F0-9+-]+)",
                options: .regularExpression
            ) else { return nil }
            let id = config[idRange].replacingOccurrences(of: "id:", with: "")
            return DisplayInfo(id: id, config: config)
        }
    }

    /// Returns the per-display `displayplacer` argument strings for an *extended*
    /// arrangement, suitable for persisting and replaying verbatim to restore it.
    ///
    /// Returns `nil` when the output is not an extended layout (mirrored, single
    /// display, or unparseable) — a mirrored snapshot does not contain the real
    /// extended positions, so there is nothing safe to capture.
    static func extendedConfigArguments(_ output: String) -> [String]? {
        let displays = parseDisplays(output)
        guard detectMode(displays) == .extended else { return nil }
        return displays.map { $0.config }
    }

    /// Mirrored = one config whose id contains "+".
    /// Extended = two configs, neither containing "+".
    /// Anything else = unknown.
    static func detectMode(_ displays: [DisplayInfo]) -> DisplayMode {
        if displays.count == 1,
           displays[0].id.range(of: "^[A-F0-9-]+\\+", options: .regularExpression) != nil {
            return .mirrored
        }
        if displays.count == 2,
           !displays[0].id.contains("+"),
           !displays[1].id.contains("+") {
            return .extended
        }
        return .unknown
    }
}
