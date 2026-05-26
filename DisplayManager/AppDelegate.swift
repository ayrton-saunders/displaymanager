import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let displayManager = DisplayManager()

    private let menuWidth: CGFloat = 240
    private var mirroredRow: MenuRowItemView?
    private var extendedRow: MenuRowItemView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "rectangle.2.swap",
            accessibilityDescription: "Display Manager"
        )

        // A real NSMenu is tracked by the system, so it pins the menu bar in full
        // screen, dismisses instantly on Mission Control / Space changes / outside
        // clicks, and renders with native Liquid Glass. Each row's NSMenuItem.view
        // hosts custom SwiftUI (see MenuRow.swift) so we keep the Control-Center
        // look on top of that native behavior.
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(.sectionHeader(title: "Display"))

        mirroredRow = addRow(to: menu, icon: "rectangle.on.rectangle", title: "Mirrored Mode") { [weak self] in
            self?.displayManager.setMirroredMode()
        }
        extendedRow = addRow(to: menu, icon: "rectangle.split.2x1", title: "Extended Mode") { [weak self] in
            self?.displayManager.setExtendedMode()
        }

        menu.addItem(.separator())

        addRow(to: menu, icon: "power", title: "Quit") {
            NSApplication.shared.terminate(nil)
        }

        statusItem?.menu = menu
    }

    @discardableResult
    private func addRow(
        to menu: NSMenu,
        icon: String,
        title: String,
        onSelect: @escaping () -> Void
    ) -> MenuRowItemView {
        let row = MenuRowItemView(icon: icon, title: title, width: menuWidth) {
            // Let the menu finish dismissing before work that may block or alert.
            DispatchQueue.main.async(execute: onSelect)
        }
        let item = NSMenuItem()
        item.view = row
        menu.addItem(item)
        return row
    }

    // Reflect the live display mode each time the menu opens: mark the active
    // mode, and disable both when no two-display arrangement is recognized
    // (single display, or an unhandled >2-display setup).
    func menuNeedsUpdate(_ menu: NSMenu) {
        let mode = displayManager.currentMode
        let canSwitch = (mode != .unknown)

        mirroredRow?.isSelected = (mode == .mirrored)
        mirroredRow?.isRowEnabled = canSwitch

        extendedRow?.isSelected = (mode == .extended)
        extendedRow?.isRowEnabled = canSwitch
    }
}
