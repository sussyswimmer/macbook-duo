import AppKit

final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Hinge")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        statusMenuItem.isEnabled = false
        statusMenuItem.isHidden = true
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Hinge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func setStatus(_ message: String?) {
        statusMenuItem.title = message ?? ""
        statusMenuItem.isHidden = message == nil
        if message != nil { item.button?.title = " –" }
    }

    /// Phase 0 debug readout: raw value and decoded angle.
    func setDebug(raw: UInt16, degrees: Double) {
        item.button?.title = String(format: " %u · %.0f°", raw, degrees)
    }
}
