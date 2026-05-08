import AppKit
import ApplicationServices
import IOKit.hidsystem

nonisolated final class KeyboardMonitor: NSObject, @unchecked Sendable {
    enum Action: Sendable {
        case decrease
        case increase
    }

    private let handler: (Action) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var retryTimer: Timer?
    private static let systemDefinedEventType = CGEventType(rawValue: UInt32(NX_SYSDEFINED))!

    init(handler: @escaping (Action) -> Void) {
        self.handler = handler
        super.init()
    }

    func start() {
        guard eventTap == nil, globalMonitor == nil else {
            return
        }

        promptForAccessibilityIfNeeded()

        if installEventTap() {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let action = Self.action(from: event) else {
                return
            }

            self?.deliver(action)
        }
        scheduleEventTapRetry()
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        retryTimer?.invalidate()

        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
        retryTimer = nil
    }

    private func installEventTap() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let eventMask = CGEventMask(1 << Self.systemDefinedEventType.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func scheduleEventTapRetry() {
        retryTimer?.invalidate()
        let timer = Timer(
            timeInterval: 2,
            target: self,
            selector: #selector(retryEventTap),
            userInfo: nil,
            repeats: true
        )
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func retryEventTap() {
        guard eventTap == nil, installEventTap() else {
            return
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func promptForAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else {
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo {
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == KeyboardMonitor.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              let action = KeyboardMonitor.action(from: nsEvent),
              let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.deliver(action)

        return nil
    }

    private func deliver(_ action: Action) {
        guard !Thread.isMainThread else {
            handler(action)
            return
        }

        RunLoop.main.perform(inModes: [.default, .eventTracking, .modalPanel]) { [weak self] in
            self?.handler(action)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private static func action(from event: NSEvent) -> Action? {
        guard event.type == .systemDefined,
              event.subtype.rawValue == 8 else {
            return nil
        }

        let keyCode = Int32((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = event.data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        guard isKeyDown else {
            return nil
        }

        switch keyCode {
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            return .decrease
        case NX_KEYTYPE_BRIGHTNESS_UP:
            return .increase
        default:
            return nil
        }
    }
}
