import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    var onToggleEnabled: (() -> Void)?
    var onToggleShowAngle: (() -> Void)?
    var onSimulate: (() -> Void)?
    /// Supplies (enabled, showAngle) when the menu opens.
    var currentFlags: (() -> (enabled: Bool, showAngle: Bool))?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let statusSeparator = NSMenuItem.separator()
    private lazy var enabledItem = makeItem("Enabled", #selector(toggleEnabled))
    private lazy var showAngleItem = makeItem("Show lid angle in menu bar", #selector(toggleShowAngle))
    private lazy var simulateItem = makeItem("Simulate lid angle…", #selector(simulate))

    private var statusMessage: String?
    private var angleText: String?

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
        menu.addItem(statusMenuItem)
        menu.addItem(statusSeparator)
        menu.addItem(enabledItem)
        menu.addItem(showAngleItem)
        menu.addItem(.separator())
        menu.addItem(simulateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Hinge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
        refreshStatusItems()
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    /// nil hides the status line.
    func setStatus(_ message: String?) {
        statusMessage = message
        refreshStatusItems()
        refreshTitle()
    }

    /// nil hides the angle text.
    func setAngle(_ degrees: Double?) {
        let text = degrees.map { String(format: " %.0f°", $0) }
        guard text != angleText else { return }
        angleText = text
        refreshTitle()
    }

    func refreshChecks(enabled: Bool, showAngle: Bool) {
        enabledItem.state = enabled ? .on : .off
        showAngleItem.state = showAngle ? .on : .off
    }

    private func refreshStatusItems() {
        statusMenuItem.title = statusMessage ?? ""
        statusMenuItem.isHidden = statusMessage == nil
        statusSeparator.isHidden = statusMessage == nil
    }

    private func refreshTitle() {
        item.button?.title = angleText ?? ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let flags = currentFlags?() { refreshChecks(enabled: flags.enabled, showAngle: flags.showAngle) }
    }

    @objc private func toggleEnabled() { onToggleEnabled?() }
    @objc private func toggleShowAngle() { onToggleShowAngle?() }
    @objc private func simulate() { onSimulate?() }
}
