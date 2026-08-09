import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

private let vendorID = 0x057E
private let productID = 0x2017
private let chatGPTBundleID = "com.openai.codex"
private let chatGPTPath = "/Applications/ChatGPT.app"
private let defaultPresetName = "ChatGPT Voice Macropad"

private enum Action: String, CaseIterable {
    case none
    case focusChatGPT
    case holdDictation
    case send
    case clearInput
    case toggleVoiceChat
    case toggleVoiceMic
    case previousChat
    case nextChat
    case toggleSidebar
    case toggleSidePanel
    case newTab
    case lockUnlock

    var displayName: String {
        switch self {
        case .none:
            return "Unassigned"
        case .focusChatGPT:
            return "Focus ChatGPT"
        case .holdDictation:
            return "Hold Dictation"
        case .send:
            return "Send"
        case .clearInput:
            return "Clear Input"
        case .toggleVoiceChat:
            return "Start/Stop Voice Chat"
        case .toggleVoiceMic:
            return "Voice Chat Mic Toggle"
        case .previousChat:
            return "Previous Chat"
        case .nextChat:
            return "Next Chat"
        case .toggleSidebar:
            return "Toggle Sidebar"
        case .toggleSidePanel:
            return "Toggle Side Panel"
        case .newTab:
            return "New Tab"
        case .lockUnlock:
            return "Lock / Unlock"
        }
    }

    var menuTitle: String {
        switch self {
        case .none:
            return displayName
        case .focusChatGPT:
            return displayName
        case .holdDictation:
            return "\(displayName) (^⇧D)"
        case .send:
            return "\(displayName) (Return)"
        case .clearInput:
            return "\(displayName) (⌘A, Delete)"
        case .toggleVoiceChat:
            return "\(displayName) (^⇧V)"
        case .toggleVoiceMic:
            return "\(displayName) (^⌥⌘M)"
        case .previousChat:
            return "\(displayName) (⇧⌘[)"
        case .nextChat:
            return "\(displayName) (⇧⌘])"
        case .toggleSidebar:
            return "\(displayName) (⌘B)"
        case .toggleSidePanel:
            return "\(displayName) (⌥⌘B)"
        case .newTab:
            return "\(displayName) (⌘T)"
        case .lockUnlock:
            return displayName
        }
    }

    var isHoldAction: Bool {
        self == .holdDictation
    }

    static let buttonChoices: [Action] = [
        .none,
        .focusChatGPT,
        .holdDictation,
        .send,
        .clearInput,
        .toggleVoiceChat,
        .toggleVoiceMic,
        .previousChat,
        .nextChat,
        .toggleSidebar,
        .toggleSidePanel,
        .newTab
    ]

    static let hatChoices: [Action] = buttonChoices.filter { !$0.isHoldAction }
}

private enum Control: String, CaseIterable {
    case a
    case b
    case x
    case y
    case l
    case r
    case zl
    case zr
    case select
    case start
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight

    var displayName: String {
        switch self {
        case .a:
            return "A"
        case .b:
            return "B"
        case .x:
            return "X"
        case .y:
            return "Y"
        case .l:
            return "L"
        case .r:
            return "R"
        case .zl:
            return "ZL"
        case .zr:
            return "ZR"
        case .select:
            return "Select"
        case .start:
            return "Start"
        case .dpadUp:
            return "D-pad Up"
        case .dpadDown:
            return "D-pad Down"
        case .dpadLeft:
            return "D-pad Left"
        case .dpadRight:
            return "D-pad Right"
        }
    }

    var defaultAction: Action {
        switch self {
        case .a:
            return .holdDictation
        case .b:
            return .send
        case .x:
            return .toggleVoiceChat
        case .y:
            return .clearInput
        case .l, .r:
            return .toggleVoiceMic
        case .zl:
            return .newTab
        case .zr:
            return .lockUnlock
        case .select, .start:
            return .focusChatGPT
        case .dpadUp:
            return .previousChat
        case .dpadDown:
            return .nextChat
        case .dpadLeft:
            return .toggleSidebar
        case .dpadRight:
            return .toggleSidePanel
        }
    }

    var isConfigurable: Bool {
        self != .zr
    }

    var isHatControl: Bool {
        switch self {
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
            return true
        default:
            return false
        }
    }

    var choices: [Action] {
        isHatControl ? Action.hatChoices : Action.buttonChoices
    }

    var storageKey: String {
        "mapping.\(rawValue)"
    }

    static let menuOrder: [Control] = [
        .a,
        .b,
        .x,
        .y,
        .l,
        .r,
        .zl,
        .zr,
        .select,
        .start,
        .dpadUp,
        .dpadDown,
        .dpadLeft,
        .dpadRight
    ]
}

private let buttonControls: [UInt32: Control] = [
    1: .b,
    2: .a,
    3: .x,
    4: .y,
    5: .l,
    6: .r,
    7: .zl,
    9: .select,
    10: .start
]

private let hatControls: [Int: Control] = [
    0: .dpadUp,
    2: .dpadRight,
    4: .dpadDown,
    6: .dpadLeft
]

private extension Dictionary where Key == Control, Value == Action {
    static var defaultMappings: [Control: Action] {
        Dictionary(uniqueKeysWithValues: Control.allCases.map { ($0, $0.defaultAction) })
    }
}

private struct KeyStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

private protocol ControllerMapperDelegate: AnyObject {
    func mapperConnectionChanged(connected: Bool, product: String?)
    func mapperEnabledChanged(enabled: Bool)
    func mapperMappingsChanged()
    func mapperDidTrigger(_ message: String)
    func mapperPermissionChanged()
}

private final class ControllerMapper {
    weak var delegate: ControllerMapperDelegate?

    var isEnabled = true {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled {
                releaseHeldButtons()
            }
            playStatusSound(enabled: isEnabled)
            delegate?.mapperEnabledChanged(enabled: isEnabled)
            delegate?.mapperDidTrigger(isEnabled ? "Unlocked" : "Locked")
        }
    }

    var hasKeyboardPermission: Bool {
        AXIsProcessTrusted()
    }

    private let manager: IOHIDManager
    private var mappings = [Control: Action].defaultMappings
    private var lastButtonValues: [UInt32: Bool] = [:]
    private var lastHatValue = 8
    private var heldButtons: [UInt32: Action] = [:]
    private var lastActionTimes: [Action: Date] = [:]
    private let actionCooldown: TimeInterval = 0.18
    private let lockToggleButtonUsage: UInt32 = 16

    init() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        loadSavedMappings()
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

    func action(for control: Control) -> Action {
        if control == .zr {
            return .lockUnlock
        }
        return mappings[control] ?? control.defaultAction
    }

    func setAction(_ action: Action, for control: Control) {
        guard control.isConfigurable, control.choices.contains(action) else { return }
        releaseHeldButtons()
        mappings[control] = action
        UserDefaults.standard.set(action.rawValue, forKey: control.storageKey)
        delegate?.mapperMappingsChanged()
        delegate?.mapperDidTrigger("\(control.displayName) → \(action.displayName)")
    }

    func loadDefaultPreset() {
        releaseHeldButtons()
        mappings = .defaultMappings
        for control in Control.allCases where control.isConfigurable {
            UserDefaults.standard.set(control.defaultAction.rawValue, forKey: control.storageKey)
        }
        lastActionTimes.removeAll()
        delegate?.mapperMappingsChanged()
        if isEnabled {
            delegate?.mapperEnabledChanged(enabled: true)
        } else {
            isEnabled = true
        }
        delegate?.mapperDidTrigger("Loaded \(defaultPresetName)")
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

    private func loadSavedMappings() {
        mappings = .defaultMappings
        for control in Control.allCases where control.isConfigurable {
            guard let rawValue = UserDefaults.standard.string(forKey: control.storageKey),
                  let action = Action(rawValue: rawValue),
                  control.choices.contains(action) else {
                continue
            }
            mappings[control] = action
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

        guard isPressed != wasPressed else { return }

        if isPressed, usage == lockToggleButtonUsage {
            isEnabled.toggle()
            return
        }

        guard isEnabled, let control = buttonControls[usage] else { return }

        let action = action(for: control)
        guard action != .none else { return }

        if action.isHoldAction {
            if isPressed {
                beginHold(button: usage, action: action)
            } else {
                endHold(button: usage)
            }
        } else if isPressed {
            trigger(action)
        }
    }

    private func handleHatSwitch(_ rawValue: CFIndex) {
        let value = Int(rawValue)
        guard value != lastHatValue else { return }
        lastHatValue = value

        guard isEnabled, let control = hatControls[value] else { return }
        trigger(action(for: control))
    }

    private func trigger(_ action: Action) {
        guard action != .none else { return }

        let now = Date()
        if let last = lastActionTimes[action], now.timeIntervalSince(last) < actionCooldown {
            return
        }
        lastActionTimes[action] = now

        delegate?.mapperDidTrigger(action.displayName)

        switch action {
        case .none:
            break
        case .focusChatGPT:
            focusChatGPT()
        case .holdDictation:
            focusThenPost(KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]))
        case .send:
            focusThenPost(KeyStroke(keyCode: 36, flags: []))
        case .clearInput:
            clearInput()
        case .toggleVoiceChat:
            focusThenPost(KeyStroke(keyCode: 9, flags: [.maskControl, .maskShift]))
        case .toggleVoiceMic:
            focusThenPost(KeyStroke(keyCode: 46, flags: [.maskControl, .maskAlternate, .maskCommand]))
        case .previousChat:
            focusThenPost(KeyStroke(keyCode: 33, flags: [.maskShift, .maskCommand]))
        case .nextChat:
            focusThenPost(KeyStroke(keyCode: 30, flags: [.maskShift, .maskCommand]))
        case .toggleSidebar:
            focusThenPost(KeyStroke(keyCode: 11, flags: [.maskCommand]))
        case .toggleSidePanel:
            focusThenPost(KeyStroke(keyCode: 11, flags: [.maskAlternate, .maskCommand]))
        case .newTab:
            focusThenPost(KeyStroke(keyCode: 17, flags: [.maskCommand]))
        case .lockUnlock:
            isEnabled.toggle()
        }
    }

    private func beginHold(button: UInt32, action: Action) {
        guard heldButtons[button] == nil else { return }
        heldButtons[button] = action
        delegate?.mapperDidTrigger("\(action.displayName) down")
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        postHoldAction(action, keyDown: true)
    }

    private func endHold(button: UInt32) {
        guard let action = heldButtons.removeValue(forKey: button) else { return }
        delegate?.mapperDidTrigger("\(action.displayName) up")
        postHoldAction(action, keyDown: false)
    }

    private func releaseHeldButtons() {
        for action in heldButtons.values {
            postHoldAction(action, keyDown: false)
        }
        heldButtons.removeAll()
    }

    private func postHoldAction(_ action: Action, keyDown: Bool) {
        switch action {
        case .holdDictation:
            postKey(KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]), keyDown: keyDown)
        default:
            break
        }
    }

    private func clearInput() {
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        post(KeyStroke(keyCode: 0, flags: [.maskCommand]))
        usleep(50_000)
        post(KeyStroke(keyCode: 51, flags: []))
    }

    private func playStatusSound(enabled: Bool) {
        let soundName = NSSound.Name(enabled ? "Tink" : "Basso")
        NSSound(named: soundName)?.play()
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
    private let presetMenuItem = NSMenuItem(title: "Preset: \(defaultPresetName)", action: nil, keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "Mapper Enabled", action: #selector(toggleEnabled), keyEquivalent: "")

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
        menu.removeAllItems()
        statusMenuItem.isEnabled = false
        keyboardMenuItem.isEnabled = false
        lastActionMenuItem.isEnabled = false
        presetMenuItem.isEnabled = false
        enabledMenuItem.target = self
        enabledMenuItem.state = mapper.isEnabled ? .on : .off
        enabledMenuItem.title = mapper.isEnabled ? "Mapper Enabled" : "Mapper Locked"

        let loadDefaultPresetItem = NSMenuItem(title: "Load Default Preset", action: #selector(loadDefaultPreset), keyEquivalent: "")
        loadDefaultPresetItem.target = self

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
        menu.addItem(presetMenuItem)
        menu.addItem(.separator())
        menu.addItem(enabledMenuItem)
        menu.addItem(loadDefaultPresetItem)
        menu.addItem(makeMappingsMenuItem())
        menu.addItem(focusItem)
        menu.addItem(requestPermissionItem)
        menu.addItem(openAccessibilityItem)
        menu.addItem(.separator())
        menu.addItem(disabledItem("Current Map"))
        for control in Control.menuOrder {
            menu.addItem(disabledItem("\(control.displayName): \(mapper.action(for: control).menuTitle)"))
        }
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.toolTip = "ChatGPT SNES Mapper"
    }

    private func makeMappingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Mappings", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Mappings")

        for control in Control.menuOrder {
            let currentAction = mapper.action(for: control)
            let controlItem = NSMenuItem(title: "\(control.displayName): \(currentAction.menuTitle)", action: nil, keyEquivalent: "")

            if control.isConfigurable {
                let controlMenu = NSMenu(title: control.displayName)
                for action in control.choices {
                    let actionItem = NSMenuItem(title: action.menuTitle, action: #selector(selectMapping(_:)), keyEquivalent: "")
                    actionItem.target = self
                    actionItem.representedObject = "\(control.rawValue)|\(action.rawValue)"
                    actionItem.state = action == currentAction ? .on : .off
                    controlMenu.addItem(actionItem)
                }
                controlItem.submenu = controlMenu
            } else {
                controlItem.isEnabled = false
            }

            submenu.addItem(controlItem)
        }

        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func updateStatusTitle() {
        guard mapper.isEnabled else {
            statusItem.button?.title = "SNES Off"
            let product = connectedProduct ?? "waiting"
            statusMenuItem.title = isConnected ? "Controller: \(product) (locked)" : "Controller: waiting (locked)"
            return
        }

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

    func mapperEnabledChanged(enabled: Bool) {
        enabledMenuItem.state = enabled ? .on : .off
        enabledMenuItem.title = enabled ? "Mapper Enabled" : "Mapper Locked"
        updateStatusTitle()
    }

    func mapperMappingsChanged() {
        buildMenu()
        updatePermissionTitle()
    }

    func mapperDidTrigger(_ message: String) {
        lastActionMenuItem.title = "Last action: \(message)"
        print("Last action: \(message)")
        fflush(stdout)
    }

    func mapperPermissionChanged() {
        updatePermissionTitle()
    }

    @objc private func selectMapping(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let control = Control(rawValue: parts[0]),
              let action = Action(rawValue: parts[1]) else {
            return
        }
        mapper.setAction(action, for: control)
    }

    @objc private func toggleEnabled() {
        mapper.isEnabled.toggle()
    }

    @objc private func loadDefaultPreset() {
        mapper.loadDefaultPreset()
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
