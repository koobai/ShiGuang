import Foundation

@MainActor
final class BrightnessViewModel {
    static let shared = BrightnessViewModel()

    private enum Storage {
        static let lastBrightnessKey = "ShiGuang.lastBrightness"

        static func savedBrightness() -> Int {
            guard let value = savedBrightnessValue() else {
                return 50
            }

            return min(100, max(0, value))
        }

        static func hasSavedBrightness() -> Bool {
            savedBrightnessValue() != nil
        }

        private static func savedBrightnessValue() -> Int? {
            UserDefaults.standard.object(forKey: lastBrightnessKey) as? Int
        }
    }

    private(set) var brightness = Storage.savedBrightness() {
        didSet {
            guard oldValue != brightness else {
                return
            }

            UserDefaults.standard.set(brightness, forKey: Storage.lastBrightnessKey)
            NotificationCenter.default.post(name: .brightnessDidChange, object: brightness)
        }
    }

    private let ddcWorker = DDCWorker()
    private var keyboardMonitor: KeyboardMonitor?

    private init() {}

    func refreshBrightness() {
        ddcWorker.readBrightness { [weak self] value in
            guard let value else {
                return
            }

            Task { @MainActor in
                self?.brightness = value
            }
        }
    }

    func restoreSavedBrightnessIfAvailable() {
        guard Storage.hasSavedBrightness() else {
            refreshBrightness()
            return
        }

        ddcWorker.setBrightness(brightness)
    }

    func setBrightness(_ value: Int) {
        let clampedValue = min(100, max(0, value))
        guard clampedValue != brightness else { return }

        brightness = clampedValue
        ddcWorker.setBrightness(clampedValue)
    }

    func startKeyboardMonitor() {
        guard keyboardMonitor == nil else {
            return
        }

        keyboardMonitor = KeyboardMonitor { [weak self] action in
            MainActor.assumeIsolated {
                self?.handleKeyboardAction(action)
            }
        }
        keyboardMonitor?.start()
    }

    func stopKeyboardMonitor() {
        keyboardMonitor?.stop()
        keyboardMonitor = nil
    }

    private func handleKeyboardAction(_ action: KeyboardMonitor.Action) {
        let step = action == .increase ? 5 : -5
        setBrightness(brightness + step)
        NotificationCenter.default.post(name: .brightnessChangedByKeyboard, object: brightness)
    }

    func resetDisplayConnection() {
        ddcWorker.resetConnection()
    }
}

nonisolated private final class DDCWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ShiGuang.DDCWorker", qos: .userInitiated)
    private let ddcManager = DDCManager()

    func readBrightness(completion: @Sendable @escaping (Int?) -> Void) {
        queue.async { [ddcManager] in
            do {
                let value = try ddcManager.readBrightnessPercent()
                DispatchQueue.main.async {
                    completion(value)
                }
            } catch {
                NSLog("ShiGuang refresh failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    func setBrightness(_ value: Int) {
        queue.async { [ddcManager] in
            do {
                try ddcManager.setBrightnessPercent(value)
            } catch {
                NSLog("ShiGuang write failed: \(error.localizedDescription)")
            }
        }
    }

    func resetConnection() {
        queue.async { [ddcManager] in
            ddcManager.resetConnection()
        }
    }
}

extension Notification.Name {
    static let brightnessDidChange = Notification.Name("ShiGuang.brightnessDidChange")
    static let brightnessChangedByKeyboard = Notification.Name("ShiGuang.brightnessChangedByKeyboard")
    static let quitRequested = Notification.Name("ShiGuang.quitRequested")
}
