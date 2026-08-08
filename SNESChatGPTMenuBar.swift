import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

private let vendorID = 0x057E
private let productID = 0x2017
private let chatGPTBundleID = "com.openai.codex"
private let chatGPTPath = "/Applications/ChatGPT.app"

private enum Action: String {
    case focusChatGPT = "focus ChatGPT"
    case toggleVoiceChat = "toggle Voice Chat"
    case toggleVoiceMic = "toggle Voice Chat microphone"
    case dictation = "dictation"
    case send = "send"
    case previousVisibleChat = "chat list up"
    case nextVisibleChat = "chat list down"
}

private struct KeyStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

private protocol ControllerMapperDelegate: AnyObject {
    func mapperConnectionChanged(connected: Bool, product: String?)
    func mapperDidTrigger(_ message: String)
    func mapperPermissionChanged()
}

private final class ControllerMapper {
    weak var delegate: ControllerMapperDelegate?

    var isEnabled = true {
        didSet {
            delegate?.mapperDidTrigger(isEnabled ? "Enabled" : "Disabled")
        }
    }

    var hasKeyboardPermission: Bool {
        AXIsProcessTrusted()
    }

    private let manager: IOHIDManager
    private var lastButtonValues: [UInt32: Bool] = [:]
    private var lastHatValue = 8
    private var heldButtons: Set<UInt32> = []
    private var lastActionTimes: [Action: Date] = [:]
    private let actionCooldown: TimeInterval = 0.18
    private var visibleChatSlot = 2
    private let visibleChatSlotKeyCodes: [Int: CGKeyCode] = [
        1: 18,
        2: 19,
        3: 20,
        4: 21,
        5: 23,
        6: 22,
        7: 26,
        8: 28,
        9: 25
    ]

    // Calibrated on this macOS host:
    // B=1, A=2, X/Y=3/4, L=5, R=6, Select=9, Start=10.
    private let buttonActions: [UInt32: Action] = [
        1: .send,            // B
        3: .toggleVoiceChat, // X / Y
        4: .toggleVoiceChat, // X / Y
        5: .toggleVoiceMic,  // L
        6: .toggleVoiceMic,  // R
        9: .focusChatGPT,    // Select
        10: .focusChatGPT    // Start
    ]
    private let heldButtonStrokes: [UInt32: KeyStroke] = [
        2: KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]) // A: hold ChatGPT dictation
    ]

    init() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let mapper = Unmanaged<ControllerMapper>.fromOpaque(context).takeUnretainedValue()
            mapper.deviceConnected(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let mapper = Unmanaged<ControllerMapper>.fromOpaque(context).takeUnretainedValue()
            mapper.deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let mapper = Unmanaged<ControllerMapper>.fromOpaque(context).takeUnretainedValue()
            mapper.inputValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            delegate?.mapperDidTrigger("Could not open HID manager: \(result)")
            return
        }

        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)
        delegate?.mapperPermissionChanged()
    }

    func requestKeyboardPermission() {
        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)
        delegate?.mapperPermissionChanged()
    }

    func focusChatGPT() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: chatGPTBundleID).first {
            app.activate(options: [.activateAllWindows])
            return
        }

        let url = URL(fileURLWithPath: chatGPTPath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error {
                self.delegate?.mapperDidTrigger("Could not open ChatGPT: \(error.localizedDescription)")
            } else {
                app?.activate(options: [.activateAllWindows])
            }
        }
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "SNES Controller"
        delegate?.mapperConnectionChanged(connected: true, product: product)
        delegate?.mapperDidTrigger("Connected: \(product)")
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "SNES Controller"
        delegate?.mapperConnectionChanged(connected: false, product: product)
        delegate?.mapperDidTrigger("Disconnected: \(product)")
    }

    private func inputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        if usagePage == kHIDPage_GenericDesktop, usage == 0x39 {
            handleHatSwitch(IOHIDValueGetIntegerValue(value))
            return
        }

        guard usagePage == kHIDPage_Button else { return }

        let isPressed = IOHIDValueGetIntegerValue(value) != 0
        let wasPressed = lastButtonValues[usage] ?? false
        lastButtonValues[usage] = isPressed

        guard isPressed != wasPressed, isEnabled else { return }

        if let stroke = heldButtonStrokes[usage] {
            if isPressed {
                beginHold(button: usage, stroke: stroke)
            } else {
                endHold(button: usage, stroke: stroke)
            }
        } else if isPressed, let action = buttonActions[usage] {
            trigger(action)
        }
    }

    private func handleHatSwitch(_ rawValue: CFIndex) {
        let value = Int(rawValue)
        guard value != lastHatValue else { return }
        lastHatValue = value

        guard isEnabled else { return }

        switch value {
        case 0:
            trigger(.previousVisibleChat)
        case 4:
            trigger(.nextVisibleChat)
        default:
            break
        }
    }

    private func trigger(_ action: Action) {
        let now = Date()
        if let last = lastActionTimes[action], now.timeIntervalSince(last) < actionCooldown {
            return
        }
        lastActionTimes[action] = now

        delegate?.mapperDidTrigger(action.rawValue)

        switch action {
        case .focusChatGPT:
            focusChatGPT()
        case .toggleVoiceChat:
            // ChatGPT default: Toggle voice chat = Control + Shift + V.
            focusThenPost(KeyStroke(keyCode: 9, flags: [.maskControl, .maskShift]))
        case .toggleVoiceMic:
            // Assign in ChatGPT Keyboard Shortcuts:
            // Toggle Voice Chat microphone = Control + Option + Command + M
            focusThenPost(KeyStroke(keyCode: 46, flags: [.maskControl, .maskAlternate, .maskCommand]))
        case .dictation:
            focusThenPost(KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]))
        case .send:
            focusThenPost(KeyStroke(keyCode: 36, flags: []))
        case .previousVisibleChat:
            stepVisibleChat(by: -1)
        case .nextVisibleChat:
            stepVisibleChat(by: 1)
        }
    }

    private func stepVisibleChat(by delta: Int) {
        visibleChatSlot = min(9, max(1, visibleChatSlot + delta))
        guard let keyCode = visibleChatSlotKeyCodes[visibleChatSlot] else { return }
        delegate?.mapperDidTrigger("chat slot \(visibleChatSlot)")
        focusThenPost(KeyStroke(keyCode: keyCode, flags: [.maskCommand]))
    }

    private func beginHold(button: UInt32, stroke: KeyStroke) {
        guard !heldButtons.contains(button) else { return }
        heldButtons.insert(button)
        delegate?.mapperDidTrigger("dictation down")
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        postKeyDown(stroke)
    }

    private func endHold(button: UInt32, stroke: KeyStroke) {
        guard heldButtons.contains(button) else { return }
        heldButtons.remove(button)
        delegate?.mapperDidTrigger("dictation up")
        postKeyUp(stroke)
    }

    private func focusThenPost(_ stroke: KeyStroke) {
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        post(stroke)
    }

    private func post(_ stroke: KeyStroke) {
        postKeyDown(stroke)
        usleep(30_000)
        postKeyUp(stroke)
    }

    private func postKeyDown(_ stroke: KeyStroke) {
        postKey(stroke, keyDown: true)
    }

    private func postKeyUp(_ stroke: KeyStroke) {
        postKey(stroke, keyDown: false)
    }

    private func postKey(_ stroke: KeyStroke, keyDown: Bool) {
        guard hasKeyboardPermission else {
            delegate?.mapperDidTrigger("Keyboard control blocked")
            delegate?.mapperPermissionChanged()
            return
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            delegate?.mapperDidTrigger("Could not create CGEventSource")
            return
        }

        guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: keyDown) else {
            return
        }
        event.flags = stroke.flags
        event.post(tap: .cghidEventTap)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, ControllerMapperDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let mapper = ControllerMapper()
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Controller: waiting", action: nil, keyEquivalent: "")
    private let keyboardMenuItem = NSMenuItem(title: "Keyboard control: checking", action: nil, keyEquivalent: "")
    private let lastActionMenuItem = NSMenuItem(title: "Last action: none", action: nil, keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")

    private var isConnected = false
    private var connectedProduct: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        mapper.delegate = self
        buildMenu()
        updateStatusTitle()
        updatePermissionTitle()
        mapper.start()
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updatePermissionTitle()
        }
    }

    private func buildMenu() {
        statusMenuItem.isEnabled = false
        keyboardMenuItem.isEnabled = false
        lastActionMenuItem.isEnabled = false
        enabledMenuItem.target = self
        enabledMenuItem.state = .on

        let focusItem = NSMenuItem(title: "Focus ChatGPT", action: #selector(focusChatGPT), keyEquivalent: "")
        focusItem.target = self

        let requestPermissionItem = NSMenuItem(title: "Request Keyboard Control Permission", action: #selector(requestKeyboardPermission), keyEquivalent: "")
        requestPermissionItem.target = self

        let openAccessibilityItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        openAccessibilityItem.target = self

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(statusMenuItem)
        menu.addItem(keyboardMenuItem)
        menu.addItem(lastActionMenuItem)
        menu.addItem(.separator())
        menu.addItem(enabledMenuItem)
        menu.addItem(focusItem)
        menu.addItem(requestPermissionItem)
        menu.addItem(openAccessibilityItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "A: hold dictation", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "B: send", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "X/Y: start/stop Voice Chat", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "L/R: Voice Chat mic toggle (^⌥⌘M)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "D-pad Up/Down: visible chat slots 1-9", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "D-pad Left/Right: unused", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Start/Select: focus ChatGPT", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.toolTip = "ChatGPT SNES Mapper"
    }

    private func updateStatusTitle() {
        let permissionMarker = mapper.hasKeyboardPermission ? "" : "!"
        statusItem.button?.title = isConnected ? "SNES\(permissionMarker)" : "SNES?"
        let product = connectedProduct ?? "waiting"
        statusMenuItem.title = isConnected ? "Controller: \(product)" : "Controller: waiting"
    }

    private func updatePermissionTitle() {
        keyboardMenuItem.title = mapper.hasKeyboardPermission ? "Keyboard control: allowed" : "Keyboard control: blocked"
        updateStatusTitle()
    }

    func mapperConnectionChanged(connected: Bool, product: String?) {
        isConnected = connected
        connectedProduct = product
        updateStatusTitle()
    }

    func mapperDidTrigger(_ message: String) {
        lastActionMenuItem.title = "Last action: \(message)"
        print("Last action: \(message)")
        fflush(stdout)
    }

    func mapperPermissionChanged() {
        updatePermissionTitle()
    }

    @objc private func toggleEnabled() {
        mapper.isEnabled.toggle()
        enabledMenuItem.state = mapper.isEnabled ? .on : .off
        statusItem.button?.title = mapper.isEnabled ? (isConnected ? "SNES" : "SNES?") : "SNES Off"
    }

    @objc private func focusChatGPT() {
        mapper.focusChatGPT()
    }

    @objc private func requestKeyboardPermission() {
        mapper.requestKeyboardPermission()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
