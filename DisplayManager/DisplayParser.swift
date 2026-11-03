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
            guard let id = displayID(in: config) else { return nil }
            return DisplayInfo(id: id, config: config)
        }
    }

    /// Extracts the `id:` value from a single per-display config string. The id may
    /// be a single hardware UUID, or a mirrored `A+B` combination.
    static func displayID(in config: String) -> String? {
        guard let idRange = config.range(
            of: "id:([A-F0-9+-]+)",
            options: .regularExpression
        ) else { return nil }
        return config[idRange].replacingOccurrences(of: "id:", with: "")
    }

    /// Returns the per-display `displayplacer` argument strings for an *extended*
    /// arrangement, suitable for persisting and replaying verbatim to restore it.
    ///
    /// Returns `nil` for any non-extended arrangement (mirrored, single display,
    /// three or more displays, or unparseable input) — a mirrored snapshot does
    /// not contain the real extended positions, so there is nothing safe to
    /// capture.
    static func extendedConfigArguments(_ output: String) -> [String]? {
        let displays = parseDisplays(output)
        guard detectMode(displays) == .extended else { return nil }
        return displays.map { $0.config }
    }

    /// The set of individual hardware display IDs present in `displayplacer list`
    /// output, expanding any mirrored `A+B` id into its components.
    static func connectedDisplayIDs(_ output: String) -> Set<String> {
        var ids = Set<String>()
        for display in parseDisplays(output) {
            for part in display.id.split(separator: "+") {
                ids.insert(String(part))
            }
        }
        return ids
    }

    /// Whether a previously-saved extended arrangement can be replayed against the
    /// currently-connected displays — i.e. every display the saved config
    /// references is still attached. Guards against replaying stale display IDs
    /// after a monitor swap, which would otherwise fail silently.
    static func savedConfigIsRestorable(_ saved: [String], against output: String) -> Bool {
        let savedIDs = Set(saved.compactMap { displayID(in: $0) })
        guard !savedIDs.isEmpty else { return false }
        return savedIDs.isSubset(of: connectedDisplayIDs(output))
    }

    /// Build a laptop-optimized mirror command, independently of which screen is
    /// primary. displayplacer's first mirror ID selects "Optimize for"; origin
    /// (0,0) selects the primary screen. Neither tells us the hardware role.
    ///
    /// An existing mirror can report the external screen's geometry for both
    /// displays. In that case only a saved extended snapshot provides a trusted
    /// laptop resolution and scaling. Do not copy the current mirror's settings.
    static func mirrorConfigArgument(_ output: String, savedExtendedConfig: [String]) -> String? {
        let displays = parseDisplays(output)
        let mode = detectMode(displays)
        let connectedIDs = connectedDisplayIDs(output)
        guard mode != .unknown, connectedIDs.count == 2 else { return nil }

        let sections = output.components(separatedBy: "Persistent screen id: ").dropFirst()
        let builtInIDs = sections.compactMap { section -> String? in
            let lines = section.components(separatedBy: .newlines)
            guard let id = lines.first,
                  lines.contains(where: { $0.hasPrefix("Type:") && $0.contains("built in screen") }),
                  connectedIDs.contains(id) else { return nil }
            return id
        }
        guard builtInIDs.count == 1, let builtInID = builtInIDs.first,
              let externalID = connectedIDs.first(where: { $0 != builtInID }) else { return nil }

        let extendedConfigs: [String]
        if mode == .extended {
            extendedConfigs = displays.map { $0.config }
        } else {
            let savedDisplays = savedExtendedConfig.compactMap { config -> DisplayInfo? in
                guard let id = displayID(in: config) else { return nil }
                return DisplayInfo(id: id, config: config)
            }
            guard savedDisplays.count == savedExtendedConfig.count,
                  detectMode(savedDisplays) == .extended,
                  Set(savedDisplays.map { $0.id }) == connectedIDs else { return nil }
            extendedConfigs = savedExtendedConfig
        }
        guard let laptopConfig = extendedConfigs.first(where: { displayID(in: $0) == builtInID }),
              !laptopConfig.contains("enabled:false") else { return nil }

        // Copy resolution, HiDPI scaling, refresh rate and color depth from the
        // laptop's extended config, not the Dell's rendering/panel resolution.
        let settings = laptopConfig.split(separator: " ").filter { token in
            ["res:", "scaling:", "hz:", "color_depth:"].contains { token.hasPrefix($0) }
        }
        guard settings.contains(where: { $0.hasPrefix("res:") }),
              settings.contains(where: { $0.hasPrefix("scaling:") }) else { return nil }
        return "id:\(builtInID)+\(externalID) \(settings.joined(separator: " ")) enabled:true origin:(0,0) degree:0"
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
