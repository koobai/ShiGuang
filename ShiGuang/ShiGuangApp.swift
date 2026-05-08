import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController(viewModel: .shared)
        controller.start()
        statusBarController = controller

        BrightnessViewModel.shared.startKeyboardMonitor()
        BrightnessViewModel.shared.restoreSavedBrightnessIfAvailable()
        installDisplayWakeObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrightnessViewModel.shared.stopKeyboardMonitor()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        statusBarController?.stop()
        statusBarController = nil
    }

    private func installDisplayWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func displayDidWake(_ notification: Notification) {
        BrightnessViewModel.shared.resetDisplayConnection()
    }
}
