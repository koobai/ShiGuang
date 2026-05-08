import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let viewModel: BrightnessViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let panelView: BrightnessMenuView
    private var observers: [NSObjectProtocol] = []
    private var autoCloseTimer: Timer?
    private var isMenuOpen = false
    private var skipNextMenuRefresh = false
    private var isStopped = false

    init(viewModel: BrightnessViewModel) {
        self.viewModel = viewModel
        panelView = BrightnessMenuView(viewModel: viewModel)
        super.init()
    }

    func start() {
        statusItem.isVisible = true
        statusItem.length = NSStatusItem.squareLength
        configureStatusButton()
        configureMenu()
        installObservers()
    }

    func stop() {
        guard !isStopped else {
            return
        }
        isStopped = true

        autoCloseTimer?.invalidate()
        autoCloseTimer = nil

        menu.cancelTrackingWithoutAnimation()
        menu.delegate = nil
        menu.removeAllItems()
        statusItem.menu = nil
        statusItem.isVisible = false
        NSStatusBar.system.removeStatusItem(statusItem)

        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        isMenuOpen = false
    }

    func requestQuit() {
        menu.cancelTrackingWithoutAnimation()
        BrightnessViewModel.shared.stopKeyboardMonitor()
        stop()

        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        // 菜单栏图标在这里调：正常只显示系统太阳图标。
        if let image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Display Brightness") {
            image.isTemplate = true
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = "☀"
        }
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        let panelItem = NSMenuItem()
        panelItem.view = panelView
        menu.addItem(panelItem)

        statusItem.menu = menu
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .brightnessDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let value = notification.object as? Int else {
                return
            }

            self?.performOnMain {
                self?.panelView.updateBrightness(value)
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .brightnessChangedByKeyboard,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let value = notification.object as? Int else {
                return
            }

            self?.performOnMain {
                self?.panelView.updateBrightness(value)
                self?.scheduleKeyboardMenu()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .quitRequested,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.performOnMain {
                self?.requestQuit()
            }
        })
    }

    nonisolated private func performOnMain(_ block: @MainActor @escaping () -> Void) {
        guard !Thread.isMainThread else {
            MainActor.assumeIsolated {
                block()
            }
            return
        }

        RunLoop.main.perform(inModes: [.default, .eventTracking, .modalPanel]) {
            MainActor.assumeIsolated {
                block()
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func scheduleKeyboardMenu() {
        RunLoop.main.perform(inModes: [.default, .eventTracking, .modalPanel]) { [weak self] in
            MainActor.assumeIsolated {
                self?.showMenu(autoClose: true)
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        guard !skipNextMenuRefresh else {
            skipNextMenuRefresh = false
            return
        }

        viewModel.refreshBrightness()
        panelView.updateBrightness(viewModel.brightness)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
    }

    private func showMenu(autoClose: Bool) {
        guard let button = statusItem.button else {
            return
        }

        autoCloseTimer?.invalidate()
        autoCloseTimer = nil

        if autoClose {
            skipNextMenuRefresh = true
            let timer = Timer(timeInterval: 1.4, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.menu.cancelTrackingWithoutAnimation()
                }
            }
            autoCloseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .eventTracking)
        }

        guard !isMenuOpen else {
            return
        }

        button.performClick(nil)
    }
}

@MainActor
private final class BrightnessMenuView: NSView {
    private let viewModel: BrightnessViewModel
    private let percentageLabel = NSTextField(labelWithString: "50%")
    private let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 76)
    }

    init(viewModel: BrightnessViewModel) {
        self.viewModel = viewModel
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 260, height: 76)))
        buildView()
        updateBrightness(viewModel.brightness)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateBrightness(_ value: Int) {
        percentageLabel.stringValue = "\(value)%"
        slider.integerValue = value
    }

    private func buildView() {
        translatesAutoresizingMaskIntoConstraints = false

        let quitButton = NSButton(
            image: NSImage(systemSymbolName: "power", accessibilityDescription: "Quit") ?? NSImage(),
            target: self,
            action: #selector(quit)
        )
        quitButton.isBordered = false

        // 百分比字号在这里调。
        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        percentageLabel.alignment = .left

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.numberOfTickMarks = 0

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [percentageLabel, spacer, quitButton])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.distribution = .fill
        headerStack.spacing = 8

        let rootStack = NSStackView(views: [headerStack, slider])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 260),
            heightAnchor.constraint(equalToConstant: 76),

            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            percentageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 62),
            headerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            quitButton.widthAnchor.constraint(equalToConstant: 24),
            quitButton.heightAnchor.constraint(equalToConstant: 24),
            slider.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    @objc private func sliderChanged() {
        viewModel.setBrightness(slider.integerValue)
        updateBrightness(viewModel.brightness)
    }

    @objc private func quit() {
        NotificationCenter.default.post(name: .quitRequested, object: nil)
    }
}
