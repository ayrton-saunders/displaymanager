import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var menuWindow: NSWindow?
    var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Display Manager")
            button.action = #selector(toggleMenu)
            button.sendAction(on: [.leftMouseDown])
        }
        
        setupMenuWindow()
    }
    
    func setupMenuWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 165),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        
        // Enable anti-aliasing and smooth rendering
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.masksToBounds = false
            contentView.layer?.allowsEdgeAntialiasing = true
            contentView.layer?.shouldRasterize = false
        }
        
        panel.contentView = NSHostingView(rootView: MenuView(closeAction: { [weak self] in
            self?.closeMenu()
        }))
        menuWindow = panel
        
        // Monitor for screenshot activity and temporarily hide window
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+Shift+3, Cmd+Shift+4, Cmd+Shift+5 (screenshot shortcuts)
            if event.modifierFlags.contains([.command, .shift]) {
                let keyCode = event.keyCode
                if keyCode == 20 || keyCode == 21 || keyCode == 23 { // 3, 4, 5 keys
                    self?.closeMenu()
                }
            }
            return event
        }
    }
    
    @objc func toggleMenu() {
        guard let button = statusItem?.button, let window = menuWindow else { return }
        
        if window.isVisible {
            closeMenu()
        } else {
            openMenu()
        }
    }
    
    func openMenu() {
        guard let button = statusItem?.button, let window = menuWindow else { return }
        
        // Highlight the button
        button.highlight(true)
        
        // Position window below menu bar button
        let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
        let windowX = buttonFrame.origin.x - (window.frame.width / 2) + (buttonFrame.width / 2)
        let windowY = buttonFrame.origin.y - window.frame.height - 2
        
        window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
        
        // Force the window to the absolute highest level
        window.level = .screenSaver
        window.orderFrontRegardless()
        
        // Start monitoring clicks outside the menu
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeMenu()
        }
    }
    
    func closeMenu() {
        guard let button = statusItem?.button, let window = menuWindow else { return }
        
        // Unhighlight the button
        button.highlight(false)
        
        window.orderOut(nil)
        
        // Stop monitoring clicks
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
