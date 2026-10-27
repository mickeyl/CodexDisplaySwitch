import AppKit
import Carbon
import CoreGraphics
import DisplayPower
import os

private let logger = Logger(subsystem: "io.github.mickeyl.CodexDisplaySwitch", category: "DisplayControl")

@MainActor
final class DisplayController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let offItem = NSMenuItem(title: "", action: #selector(turnOff), keyEquivalent: "")
    private let onItem = NSMenuItem(title: "", action: #selector(turnOn), keyEquivalent: "")
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(quitApp), keyEquivalent: "")
    private let sleepAssertions = SleepAssertions()
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var offSignal: DispatchSourceSignal?
    private var onSignal: DispatchSourceSignal?
    private var keyboardTimer: Timer?
    private var lastKeyDownCount: UInt32 = 0
    private var lastModifierCount: UInt32 = 0
    private var busy = false
    private var pendingWake = false
    private var isOff = UserDefaults.standard.bool(forKey: "displaysOff")

    func applicationDidFinishLaunching(_ notification: Notification) {
        offItem.title = localized("menu.turnOff")
        onItem.title = localized("menu.turnOn")
        offItem.target = self
        onItem.target = self
        menu.addItem(offItem)
        menu.addItem(onItem)
        menu.addItem(.separator())
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        let shortcut = NSMenuItem(title: localized("menu.shortcut"), action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)
        let wakeHint = NSMenuItem(title: localized("menu.wakeHint"), action: nil, keyEquivalent: "")
        wakeHint.isEnabled = false
        menu.addItem(wakeHint)
        menu.addItem(.separator())
        quitItem.title = localized("menu.quit")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updateMenu()
        registerHotKey()
        registerSignals()
        if isOff { _ = sleepAssertions.acquire() }
        snapshotKeyboardCounters()
        keyboardTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkKeyboardWake() }
        }
        logger.info("Display switch launched")
    }

    @objc private func turnOff() { setDisplaysOff(true) }
    @objc private func turnOn() { setDisplaysOff(false) }
    @objc private func quitApp() { NSApp.terminate(nil) }

    fileprivate func toggle() { setDisplaysOff(!isOff) }

    private func setDisplaysOff(_ off: Bool) {
        if busy {
            if !off { pendingWake = true }
            return
        }
        if off && !sleepAssertions.acquire() {
            stateItem.title = localized("menu.cannotStayAwake")
            return
        }
        busy = true
        updateMenu()
        logger.info("Switch requested: \(off ? "off" : "on")")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = off ? DisplayPower.turnOff() : DisplayPower.turnOn()
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if off && result.attempted > 0 {
                    self.isOff = true
                } else if !off && result.succeeded {
                    self.isOff = false
                }
                if !self.isOff { self.sleepAssertions.release() }
                UserDefaults.standard.set(self.isOff, forKey: "displaysOff")
                self.snapshotKeyboardCounters()
                self.updateMenu()
                if !result.failures.isEmpty {
                    logger.error("Display control issue: \(result.failures.joined(separator: "; "), privacy: .public)")
                    self.stateItem.title = self.localized("menu.checkDisplays")
                }
                if self.pendingWake {
                    self.pendingWake = false
                    self.setDisplaysOff(false)
                }
            }
        }
    }

    private func updateMenu() {
        offItem.isEnabled = !busy && !isOff
        onItem.isEnabled = !busy && isOff
        quitItem.isEnabled = !busy && !isOff
        stateItem.title = busy ? localized("menu.switching") :
            (isOff ? localized("menu.displaysOff") : localized("menu.displaysOn"))
        statusItem.button?.image = NSImage(
            systemSymbolName: isOff ? "display.slash" : "display",
            accessibilityDescription: isOff ? localized("menu.displaysOff") : localized("menu.displaysOn")
        )
        statusItem.button?.toolTip = isOff ? localized("menu.wakeHint") : localized("menu.shortcut")
    }

    private func registerHotKey() {
        let id = EventHotKeyID(signature: OSType(0x43445357), id: 1)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        guard RegisterEventHotKey(UInt32(kVK_ANSI_D), modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            logger.error("Global shortcut registration failed")
            stateItem.title = localized("menu.shortcutUnavailable")
            return
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<DisplayController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.toggle() }
            return noErr
        }, 1, &spec, context, &hotKeyHandler)
    }

    private func registerSignals() {
        signal(SIGUSR1, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)
        let off = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        off.setEventHandler { [weak self] in self?.setDisplaysOff(true) }
        off.resume()
        offSignal = off
        let on = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        on.setEventHandler { [weak self] in self?.setDisplaysOff(false) }
        on.resume()
        onSignal = on
    }

    private func snapshotKeyboardCounters() {
        lastKeyDownCount = CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown)
        lastModifierCount = CGEventSource.counterForEventType(.hidSystemState, eventType: .flagsChanged)
    }

    private func checkKeyboardWake() {
        guard isOff, !busy else { return }
        let keyCount = CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown)
        let modifierCount = CGEventSource.counterForEventType(.hidSystemState, eventType: .flagsChanged)
        guard keyCount != lastKeyDownCount || modifierCount != lastModifierCount else { return }
        setDisplaysOff(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardTimer?.invalidate()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if isOff { _ = DisplayPower.turnOn() }
        sleepAssertions.release()
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
