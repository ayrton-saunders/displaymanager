import Foundation
import Combine
import AppKit

class DisplayManager: ObservableObject {
    @Published var currentMode: DisplayMode = .unknown
    private var savedExtendedConfig: [String] = []

    init() {
        // Process.waitUntilExit() pumps the run loop. Running it inside
        // @StateObject construction re-enters SwiftUI's view-graph setup
        // and trips AttributeGraph cycle warnings. Defer to the next turn.
        DispatchQueue.main.async { [weak self] in
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

        // If already in extended mode (2 separate configs), save them
        if displayConfigs.count == 2 && !displayConfigs[0].id.contains("+") && !displayConfigs[1].id.contains("+") {
            savedExtendedConfig = displayConfigs.map { $0.config }
            print("DEBUG: Saved extended config for later restoration")
        }
        
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
        // If we have saved extended config, use it
        if !savedExtendedConfig.isEmpty {
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
                
                // Consider it successful even with warnings (exit code may not be 0)
                currentMode = .extended
            } catch {
                showAlert(message: "Error setting extended mode: \(error.localizedDescription)")
            }
            return
        }
        
        // Otherwise parse the current config and separate the displays
        let displays = DisplayParser.parseDisplays(output)
        guard !displays.isEmpty else {
            showAlert(message: "Could not parse display configuration")
            return
        }

        if displays.count == 1 {
            let config = displays[0].config
            let combinedId = displays[0].id

            // Split the IDs
            let ids = combinedId.split(separator: "+").map(String.init)
            if ids.count == 2 {
                let builtInId = ids[0]
                let externalId = ids[1]

                // Get the resolution from the config
                let resPattern = "res:(\\d+x\\d+)"
                var resolution = "1728x1117"  // Default MacBook resolution
                if let resRange = config.range(of: resPattern, options: .regularExpression) {
                    resolution = String(config[resRange]).replacingOccurrences(of: "res:", with: "")
                }

                // Create separate configs for each display
                // Built-in display keeps the current resolution
                var builtInConfig = config
                    .replacingOccurrences(of: "id:\(combinedId)", with: "id:\(builtInId)")
                builtInConfig += " origin:(0,0) degree:0"

                // External display - use a safe resolution (2560x1440 for Dell S2725QC)
                var externalConfig = config
                    .replacingOccurrences(of: "id:\(combinedId)", with: "id:\(externalId)")
                // Replace the resolution with external display's native resolution
                externalConfig = externalConfig.replacingOccurrences(of: "res:\(resolution)", with: "res:2560x1440")
                externalConfig += " origin:(0,-1440) degree:0"

                print("DEBUG: Built-in config: \(builtInConfig)")
                print("DEBUG: External config: \(externalConfig)")

                let extendedTask = Process()
                extendedTask.executableURL = URL(fileURLWithPath: displayplacerPath)
                extendedTask.arguments = [builtInConfig, externalConfig]

                let errorPipe = Pipe()
                extendedTask.standardError = errorPipe

                do {
                    try extendedTask.run()
                    extendedTask.waitUntilExit()

                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                    print("DEBUG: Extended mode exit code: \(extendedTask.terminationStatus)")
                    print("DEBUG: Extended mode error output: \(errorOutput)")

                    // Consider it successful even with warnings
                    currentMode = .extended
                } catch {
                    showAlert(message: "Error setting extended mode: \(error.localizedDescription)")
                }
                return
            }
        }
        
        showAlert(message: "Could not parse mirrored display configuration")
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
