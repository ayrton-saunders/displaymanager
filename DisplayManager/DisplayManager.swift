import Foundation
import Combine
import AppKit

class DisplayManager: ObservableObject {
    @Published var currentMode: DisplayMode = .unknown

    /// The last real extended arrangement we observed, as verbatim `displayplacer`
    /// argument strings. Persisted so it survives app restarts — the previous
    /// in-memory-only version was wiped on every launch, which forced the
    /// hardcoded-origin fallback and caused the external display to jump.
    private let savedConfigKey = "savedExtendedConfig"
    private var savedExtendedConfig: [String] {
        get { UserDefaults.standard.stringArray(forKey: savedConfigKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: savedConfigKey) }
    }

    /// Capture and persist the extended arrangement whenever we see one, so it can
    /// be replayed exactly on the next un-mirror.
    private func captureExtendedConfigIfPresent(_ output: String) {
        if let args = DisplayParser.extendedConfigArguments(output) {
            savedExtendedConfig = args
            print("DEBUG: Captured extended config for restoration: \(args)")
        }
    }

    init() {
        // Process.waitUntilExit() pumps the run loop. Running it inside
        // @StateObject construction re-enters SwiftUI's view-graph setup
        // and trips AttributeGraph cycle warnings. Defer to the next turn.
        DispatchQueue.main.async { [weak self] in
            self?.refreshMode()
        }

        // Re-poll whenever the display arrangement changes while the app is
        // running, so a layout the user sets up in System Settings is captured
        // automatically (refreshMode persists any extended config it sees).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMode()
        }
    }

    private func refreshMode() {
        let possiblePaths = [
            "/opt/homebrew/bin/displayplacer",
            "/usr/local/bin/displayplacer",
            "/usr/bin/displayplacer"
        ]
        guard let path = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["list"]
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return
        }
        let displays = DisplayParser.parseDisplays(output)
        currentMode = DisplayParser.detectMode(displays)
        captureExtendedConfigIfPresent(output)
        print("DEBUG: Initial mode detected: \(currentMode)")
    }

    func setMirroredMode() {
        executeDisplayplacer(mirror: true)
    }
    
    func setExtendedMode() {
        executeDisplayplacer(mirror: false)
    }
    
    private func executeDisplayplacer(mirror: Bool) {
        let possiblePaths = [
            "/opt/homebrew/bin/displayplacer",
            "/usr/local/bin/displayplacer",
            "/usr/bin/displayplacer"
        ]
        
        var displayplacerPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                displayplacerPath = path
                break
            }
        }
        
        guard let path = displayplacerPath else {
            showAlert(message: "displayplacer not found. Please install it using: brew install displayplacer")
            return
        }
        
        if mirror {
            executeMirrorCommand(displayplacerPath: path)
        } else {
            executeExtendedCommand(displayplacerPath: path)
        }
    }
    
    private func executeMirrorCommand(displayplacerPath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: displayplacerPath)
        task.arguments = ["list"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                parseMirrorCommand(from: output, displayplacerPath: displayplacerPath)
            } else if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                showAlert(message: "displayplacer error: \(error)")
            } else {
                showAlert(message: "No output from displayplacer")
            }
        } catch {
            showAlert(message: "Error executing displayplacer: \(error.localizedDescription)")
        }
    }
    
    private func parseMirrorCommand(from output: String, displayplacerPath: String) {
        print("DEBUG: Full output from displayplacer list:")
        print(output)
        print("DEBUG: End of output")

        let displays = DisplayParser.parseDisplays(output)
        for display in displays {
            print("DEBUG: Found display - ID: \(display.id), Config: \(display.config)")
        }
        guard !displays.isEmpty else {
            showAlert(message: "Could not parse display configuration. Check Console.app for debug output.")
            return
        }
        let displayConfigs: [(id: String, config: String)] = displays.map { ($0.id, $0.config) }

        print("DEBUG: Total displays found: \(displayConfigs.count)")

        // If we're mirroring from an extended layout, capture it first so we can
        // restore the exact arrangement when the user un-mirrors.
        captureExtendedConfigIfPresent(output)

        // For mirroring, we need the individual display IDs
        // If currently mirrored, we need to extract them from the combined ID
        var builtInId: String = ""
        var externalId: String = ""
        var builtInConfig: String = ""
        
        if displayConfigs.count == 1 && displayConfigs[0].id.contains("+") {
            // Currently mirrored - extract individual IDs
            let ids = displayConfigs[0].id.split(separator: "+").map(String.init)
            if ids.count == 2 {
                builtInId = ids[0]
                externalId = ids[1]
                // Use the mirrored config as base
                builtInConfig = displayConfigs[0].config
                    .replacingOccurrences(of: "id:\(displayConfigs[0].id)", with: "id:\(builtInId)")
            }
        } else if displayConfigs.count >= 2 {
            // Currently extended - identify which is which
            for display in displayConfigs {
                if display.config.contains("origin:(0,0)") {
                    builtInId = display.id
                    builtInConfig = display.config
                } else {
                    externalId = display.id
                }
            }
        }
        
        guard !builtInId.isEmpty && !externalId.isEmpty else {
            showAlert(message: "Could not identify display IDs")
            return
        }
        
        // For mirroring, the built-in display should be the main display
        // External display mirrors the built-in display
        let mirrorId = "\(builtInId)+\(externalId)"
        var mirrorConfig = builtInConfig
        
        // Replace the built-in display's ID with the combined mirror ID
        mirrorConfig = mirrorConfig.replacingOccurrences(of: "id:\(builtInId)", with: "id:\(mirrorId)")
        
        // Remove origin and degree for mirroring (not needed)
        mirrorConfig = mirrorConfig.replacingOccurrences(of: #"origin:\([^)]+\)\s*"#, with: "", options: .regularExpression)
        mirrorConfig = mirrorConfig.replacingOccurrences(of: #"degree:\d+\s*"#, with: "", options: .regularExpression)
        
        print("DEBUG: Mirror config: \(mirrorConfig)")
        
        let mirrorTask = Process()
        mirrorTask.executableURL = URL(fileURLWithPath: displayplacerPath)
        mirrorTask.arguments = [mirrorConfig]
        
        let errorPipe = Pipe()
        mirrorTask.standardError = errorPipe
        
        do {
            try mirrorTask.run()
            mirrorTask.waitUntilExit()
            
            if mirrorTask.terminationStatus == 0 {
                currentMode = .mirrored
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                showAlert(message: "Failed to enable mirrored mode: \(errorOutput)")
            }
        } catch {
            showAlert(message: "Error setting mirror mode: \(error.localizedDescription)")
        }
    }
    
    private func executeExtendedCommand(displayplacerPath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: displayplacerPath)
        task.arguments = ["list"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                parseExtendedCommand(from: output, displayplacerPath: displayplacerPath)
            } else if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                showAlert(message: "displayplacer error: \(error)")
            } else {
                showAlert(message: "No output from displayplacer")
            }
        } catch {
            showAlert(message: "Error executing displayplacer: \(error.localizedDescription)")
        }
    }
    
    private func parseExtendedCommand(from output: String, displayplacerPath: String) {
        // Replay the saved arrangement, but only if every display it references is
        // still connected. After a monitor swap the saved IDs are stale and
        // replaying them would silently fail — fall through to the alert instead.
        // We validate against the `output` we already fetched (no extra list call).
        if DisplayParser.savedConfigIsRestorable(savedExtendedConfig, against: output) {
            print("DEBUG: Using saved extended configuration")
            let extendedTask = Process()
            extendedTask.executableURL = URL(fileURLWithPath: displayplacerPath)
            extendedTask.arguments = savedExtendedConfig

            let errorPipe = Pipe()
            extendedTask.standardError = errorPipe

            do {
                try extendedTask.run()
                extendedTask.waitUntilExit()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                print("DEBUG: Extended mode exit code: \(extendedTask.terminationStatus)")
                print("DEBUG: Extended mode error output: \(errorOutput)")

                if extendedTask.terminationStatus == 0 {
                    currentMode = .extended
                } else {
                    let detail = errorOutput.isEmpty
                        ? "displayplacer exited with status \(extendedTask.terminationStatus)"
                        : errorOutput
                    showAlert(message: "Failed to restore extended mode: \(detail)")
                }
            } catch {
                showAlert(message: "Error setting extended mode: \(error.localizedDescription)")
            }
            return
        }

        // No saved arrangement. A mirrored snapshot does not contain the real
        // extended positions, so we cannot reconstruct them without guessing —
        // and guessing (the old hardcoded origin) is exactly what moved the
        // external display. Ask the user to establish the layout once; we capture
        // it automatically thereafter.
        showAlert(message: """
        No saved extended arrangement to restore yet.

        Arrange your displays in extended mode once (via System Settings ▸ Displays, \
        or while the app is running), and Display Manager will remember the exact \
        layout for next time.
        """)
    }
    
    private func showAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Display Manager"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
