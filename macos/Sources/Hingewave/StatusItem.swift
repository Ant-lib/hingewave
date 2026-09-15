import AppKit
import ServiceManagement

/// Menu bar presence: current angle, Follow the Lid, Preview Fold, Launch at Login, Quit.
final class StatusItemController: NSObject {
    static let followLidKey = "followLid"

    private let item: NSStatusItem
    private let controller: AppController?
    private let sensorAvailable: Bool
    private let angleItem = NSMenuItem(title: "Waiting for the lid", action: nil, keyEquivalent: "")
    private let followItem = NSMenuItem(title: "Follow the Lid", action: #selector(toggleFollow), keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "Preview Fold", action: #selector(preview), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    init(controller: AppController?, sensorAvailable: Bool) {
        self.controller = controller
        self.sensorAvailable = sensorAvailable
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Hingewave")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        angleItem.isEnabled = false
        menu.addItem(angleItem)
        menu.addItem(.separator())
        for mi in [followItem, previewItem, loginItem] {
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Hingewave", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu

        if !sensorAvailable {
            angleItem.title = "No lid angle sensor on this Mac"
            followItem.isEnabled = false
        }
        refresh()
    }

    func update(angle: Double) {
        angleItem.title = String(format: "Lid: %.0f deg", angle)
        item.button?.toolTip = angleItem.title
    }

    private func refresh() {
        let follow = controller?.followLid ?? false
        followItem.state = follow ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: Actions

    @objc private func toggleFollow() {
        guard let controller else { return }
        if !controller.followLid && !ScreenStreamer.hasPermission() {
            explainPermission()
            ScreenStreamer.requestPermission()
        }
        controller.followLid.toggle()
        UserDefaults.standard.set(controller.followLid, forKey: Self.followLidKey)
        refresh()
    }

    @objc private func preview() {
        // Re-run this executable with the scripted sweep. A child of the app keeps
        // the app's Screen Recording grant; without the grant it plays the demo picture.
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let task = Process()
        task.executableURL = exe
        task.arguments = ScreenStreamer.hasPermission() ? ["--simulate-close"] : ["--demo"]
        do {
            try task.run()
        } catch {
            Log.info("preview failed to launch: \(error)")
        }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Log.info("launch at login change failed: \(error)")
        }
        refresh()
    }

    private func explainPermission() {
        let alert = NSAlert()
        alert.messageText = "Hingewave needs Screen Recording"
        alert.informativeText = "It captures the built-in display only while the lid is moving so it can redraw the desktop as it folds. Nothing is stored or sent anywhere. Turn on Hingewave under System Settings, Privacy and Security, Screen Recording."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
