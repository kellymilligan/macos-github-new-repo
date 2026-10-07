import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = NewRepoModel()
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon (LSUIElement also covers this when bundled).
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New GitHub repository")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hostingController = NSHostingController(
            rootView: ContentView(model: model, close: { [weak self] in self?.closePopover() })
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        // Closed manually (see below) so the folder picker doesn't dismiss the popover.
        popover.behavior = .applicationDefined
        popover.animates = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        model.popoverDidOpen()

        // Clicks in other apps close the popover. Clicks in our own windows
        // (e.g. the folder picker) aren't seen by a global monitor.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func closePopover() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        popover.performClose(nil)
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        closePopover()
    }
}
