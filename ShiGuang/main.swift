import AppKit

private let app = NSApplication.shared
private let appDelegate = AppDelegate()

app.setActivationPolicy(.accessory)
app.delegate = appDelegate
app.run()
