import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isOn = false
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private lazy var settingsWindow = SettingsWindowController()

    private var clamshellMonitor: ClamshellMonitor?
    private static let savedBrightnessKey = "wedge.savedBrightness"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installSignalHandlers()
        recoverBrightnessIfPreviousRunCrashed()
        setupStatusItem()
        setupMenu()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort: if a wedge was in, pull it on quit so the user doesn't
        // ship a Mac that never sleeps after uninstall. Also restore any
        // brightness we forced to zero while the lid was closed.
        if isOn, let password = KeychainStore.load() {
            SleepController.forceCleanup(password: password)
        }
        restoreBrightnessOnExit()
    }

    // MARK: - UI

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenubarIcon.image(isOn: false)
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = L10n.tr("Wedge — keep your Mac open")
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }

    private func setupMenu() {
        menu = NSMenu()

        statusMenuItem = NSMenuItem(title: L10n.tr("Lid free to close"), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(
            title: L10n.tr("Wedge it open"),
            action: #selector(toggle),
            keyEquivalent: "w"
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L10n.tr("Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.tr("Quit Wedge"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

    }

    private func refreshUI() {
        statusItem.button?.image = MenubarIcon.image(isOn: isOn)
        statusItem.button?.image?.isTemplate = true
        statusMenuItem.title = isOn
            ? L10n.tr("Wedged open — Mac stays awake")
            : L10n.tr("Lid free to close")
        toggleMenuItem.title = isOn
            ? L10n.tr("Pull the wedge")
            : L10n.tr("Wedge it open")
    }

    // MARK: - Status item interaction

    private var activeWedgePanel: WedgePanel?
    private let dragThreshold: CGFloat = 32

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let isRightClick = event.type == .rightMouseDown
            || event.modifierFlags.contains(.control)
        if isRightClick {
            showContextMenu()
            return
        }
        runDragInteraction(from: sender)
    }

    private func showContextMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    private func runDragInteraction(from button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)
        let anchor = CGPoint(x: buttonRectOnScreen.midX, y: buttonRectOnScreen.minY)

        let startMouse = NSEvent.mouseLocation
        let dragStartDeadzone: CGFloat = 4
        let originalIsOn = isOn

        var panel: WedgePanel?
        var maxDistance: CGFloat = 0
        var crossedThreshold = false

        trackLoop: while true {
            guard let next = NSApp.nextEvent(
                matching: [.leftMouseUp, .leftMouseDragged],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { continue }

            let location = NSEvent.mouseLocation
            switch next.type {
            case .leftMouseDragged:
                let dist = hypot(location.x - startMouse.x, location.y - startMouse.y)
                maxDistance = max(maxDistance, dist)
                guard dist > dragStartDeadzone else { continue }
                if panel == nil {
                    let p = WedgePanel(anchorOnScreen: anchor, isOn: isOn)
                    p.show()
                    panel = p
                    activeWedgePanel = p
                }
                let progress = min(1.0, Double(dist / dragThreshold))
                panel?.updateTip(location, armProgress: progress)
                // The menubar lid follows the pull in real time.
                let liveLid: Double = originalIsOn ? (1.0 - progress) : progress
                statusItem.button?.image = MenubarIcon.image(lidProgress: liveLid)
                statusItem.button?.image?.isTemplate = true
                // Click feedback the moment the cord crosses the commit point.
                if !crossedThreshold && dist >= dragThreshold {
                    crossedThreshold = true
                    NSSound(named: "Tink")?.play()
                }
            case .leftMouseUp:
                break trackLoop
            default:
                break
            }
        }

        let didDrag = maxDistance >= dragThreshold

        guard let activePanel = panel else {
            // No real drag — treat as a regular click, show the menu.
            showContextMenu()
            return
        }

        activePanel.snapBack { [weak self] in
            self?.activeWedgePanel = nil
            guard let self else { return }
            if didDrag {
                Task { @MainActor in await self.performToggle() }
            } else {
                // Cancelled — revert the menubar lid to its starting state.
                self.refreshUI()
            }
        }
    }

    // MARK: - Actions

    @objc private func toggle() {
        Task { @MainActor in
            await performToggle()
        }
    }

    private func performToggle() async {
        let target = !isOn
        guard let password = obtainPassword() else { return }

        do {
            try SleepController.setDisableSleep(target, password: password)
            isOn = target
            refreshUI()
            if target {
                startBrightnessGuard()
            } else {
                stopBrightnessGuard()
            }
        } catch SleepError.invalidPassword {
            KeychainStore.delete()
            showError(
                title: L10n.tr("Password rejected"),
                message: L10n.tr("Your saved password didn't work. Try again — Wedge will ask once more.")
            )
        } catch SleepError.pmsetFailed(let code, let stderr) {
            showError(
                title: String(format: L10n.tr("pmset failed (exit %d)"), Int(code)),
                message: stderr.isEmpty ? L10n.tr("Unknown error from pmset.") : stderr
            )
        } catch {
            showError(title: L10n.tr("Unexpected error"), message: "\(error)")
        }
    }

    private func obtainPassword() -> String? {
        if let cached = KeychainStore.load() { return cached }
        guard let entered = PasswordPrompt.ask(
            reason: L10n.tr("Wedge uses pmset to keep your Mac from sleeping. macOS requires admin rights for this.")
        ) else { return nil }

        guard SleepController.validate(password: entered) else {
            showError(
                title: L10n.tr("Wrong password"),
                message: L10n.tr("macOS didn't accept that password.")
            )
            return nil
        }

        KeychainStore.save(password: entered)
        return entered
    }

    @objc private func openSettings() {
        settingsWindow.showAndFocus()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Brightness guard

    /// While Wedge is ON, watches the lid. On close: save current brightness
    /// and force it to 0 so the screen stops burning battery under the closed
    /// lid (pmset disablesleep keeps the display awake too). On open: restore.
    /// Skipped entirely if the user has disabled the dim-on-close preference.
    private func startBrightnessGuard() {
        guard Preferences.dimDisplayOnLidClose else { return }
        guard clamshellMonitor == nil else { return }
        let monitor = ClamshellMonitor()
        monitor.onStateChange = { [weak self] isOpen in
            self?.handleClamshell(isOpen: isOpen)
        }
        clamshellMonitor = monitor
    }

    private func stopBrightnessGuard() {
        clamshellMonitor = nil
        restoreSavedBrightness()
    }

    private func handleClamshell(isOpen: Bool) {
        if isOpen {
            restoreSavedBrightness()
        } else {
            if Self.loadSavedBrightness() == nil,
               let current = BrightnessController.getBrightness() {
                Self.persistSavedBrightness(current)
            }
            BrightnessController.setBrightness(0)
        }
    }

    private func restoreSavedBrightness() {
        guard let saved = Self.loadSavedBrightness() else { return }
        BrightnessController.setBrightness(saved)
        Self.clearSavedBrightness()
    }

    private static func loadSavedBrightness() -> Float? {
        let value = UserDefaults.standard.float(forKey: savedBrightnessKey)
        // float(forKey:) returns 0 when missing, distinguish via object check.
        guard UserDefaults.standard.object(forKey: savedBrightnessKey) != nil else { return nil }
        return value
    }

    private static func persistSavedBrightness(_ value: Float) {
        UserDefaults.standard.set(value, forKey: savedBrightnessKey)
    }

    private static func clearSavedBrightness() {
        UserDefaults.standard.removeObject(forKey: savedBrightnessKey)
    }

    /// If we crashed last run with the lid closed, brightness is still stuck at
    /// 0 right now. Detect the leftover value and restore it on launch.
    private func recoverBrightnessIfPreviousRunCrashed() {
        guard let saved = Self.loadSavedBrightness() else { return }
        BrightnessController.setBrightness(saved)
        Self.clearSavedBrightness()
    }

    private func restoreBrightnessOnExit() {
        restoreSavedBrightness()
    }

    // MARK: - Safety nets

    private func installSignalHandlers() {
        // pmset disablesleep persists across processes. If we get SIGTERM/SIGINT,
        // try to release the lock before dying.
        let handler: @convention(c) (Int32) -> Void = { _ in
            if let password = KeychainStore.load() {
                SleepController.forceCleanup(password: password)
            }
            _exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
        signal(SIGHUP, handler)
    }
}
