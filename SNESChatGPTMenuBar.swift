import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

private let nintendoVendorID = 0x057E
private let snesProductID = 0x2017
private let joyConRightProductID = 0x2007
private let chatGPTBundleID = "com.openai.codex"
private let chatGPTPath = "/Applications/ChatGPT.app"
private let defaultPresetName = "ChatGPT Voice Macropad"
private let controllerSelectionStorageKey = "controllerSelection"

private enum Action: String, CaseIterable {
    case none
    case focusChatGPT
    case holdDictation
    case send
    case clearInput
    case toggleVoiceChat
    case toggleVoiceMic
    case expandBrowserContentPanel
    case previousChat
    case nextChat
    case toggleSidebar
    case toggleSidePanel
    case newChat
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
        case .expandBrowserContentPanel:
            return "Expand Browser/Content Panel"
        case .previousChat:
            return "Previous Chat"
        case .nextChat:
            return "Next Chat"
        case .toggleSidebar:
            return "Toggle Sidebar"
        case .toggleSidePanel:
            return "Toggle Side Panel"
        case .newChat:
            return "New Chat"
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
        case .expandBrowserContentPanel:
            return "\(displayName) (^⌘Z)"
        case .previousChat:
            return "\(displayName) (⇧⌘[)"
        case .nextChat:
            return "\(displayName) (⇧⌘])"
        case .toggleSidebar:
            return "\(displayName) (⌘B)"
        case .toggleSidePanel:
            return "\(displayName) (⌥⌘B)"
        case .newChat:
            return "\(displayName) (⌘N)"
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
        .expandBrowserContentPanel,
        .previousChat,
        .nextChat,
        .toggleSidebar,
        .toggleSidePanel,
        .newChat,
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
            return .newChat
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

    var legacyStorageKey: String {
        "mapping.\(rawValue)"
    }

    func storageKey(productID: Int) -> String {
        "mapping.\(productID).\(rawValue)"
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
    3: .y,
    4: .x,
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

private struct InputKey: Hashable {
    let deviceID: Int
    let usage: UInt32
}

private struct ControllerProfile {
    let productID: Int
    let name: String
    let statusLabel: String
    let buttonControls: [UInt32: Control]
    let hatControls: [Int: Control]
    let lockButtonUsage: UInt32
    let controlNames: [Control: String]
    let defaultActionOverrides: [Control: Action]

    func defaultAction(for control: Control) -> Action {
        defaultActionOverrides[control] ?? control.defaultAction
    }
}

private enum ControllerSelection: String, CaseIterable {
    case automatic
    case snes
    case joyConRight

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .snes:
            return "SNES Controller"
        case .joyConRight:
            return "Joy-Con (R)"
        }
    }

    var productID: Int? {
        switch self {
        case .automatic:
            return nil
        case .snes:
            return snesProductID
        case .joyConRight:
            return joyConRightProductID
        }
    }

    func accepts(_ profile: ControllerProfile) -> Bool {
        productID == nil || productID == profile.productID
    }
}

private let snesProfile = ControllerProfile(
    productID: snesProductID,
    name: "Nintendo SNES Controller",
    statusLabel: "SNES",
    buttonControls: buttonControls,
    hatControls: hatControls,
    lockButtonUsage: 16,
    controlNames: [:],
    defaultActionOverrides: [:]
)

// Hardware-calibrated on a Nintendo Switch Joy-Con (R) connected over
// Bluetooth to macOS. Its vertical stick orientation rotates the hat values
// 90 degrees from the SNES controller.
private let joyConRightProfile = ControllerProfile(
    productID: joyConRightProductID,
    name: "Nintendo Switch Joy-Con (R)",
    statusLabel: "JOY",
    buttonControls: [
        1: .a,
        3: .b,
        2: .x,
        4: .y,
        5: .l,      // SL
        6: .r,      // SR
        15: .zl,    // R
        16: .zr,    // ZR
        13: .select, // Home
        10: .start   // +
    ],
    hatControls: [
        2: .dpadUp,
        4: .dpadRight,
        6: .dpadDown,
        0: .dpadLeft
    ],
    lockButtonUsage: 16,
    controlNames: [
        .l: "SL",
        .r: "SR",
        .zl: "R",
        .zr: "ZR",
        .select: "Home",
        .start: "+",
        .dpadUp: "Stick Up",
        .dpadDown: "Stick Down",
        .dpadLeft: "Stick Left",
        .dpadRight: "Stick Right"
    ],
    defaultActionOverrides: [
        .r: .expandBrowserContentPanel, // SR
        .zl: .toggleVoiceMic,           // R
        .start: .newChat                // +
    ]
)

private let controllerProfiles: [Int: ControllerProfile] = [
    snesProfile.productID: snesProfile,
    joyConRightProfile.productID: joyConRightProfile
]

private func printDefaultMappingsAndExit() -> Never {
    for profile in controllerProfiles.values.sorted(by: { $0.productID < $1.productID }) {
        for control in Control.menuOrder {
            let name = profile.controlNames[control] ?? control.displayName
            let action = profile.defaultAction(for: control)
            print("\(profile.statusLabel).\(control.rawValue).\(name)=\(action.rawValue)")
        }
    }
    exit(EXIT_SUCCESS)
}

private extension Dictionary where Key == Control, Value == Action {
    static func defaultMappings(for profile: ControllerProfile) -> [Control: Action] {
        Dictionary(uniqueKeysWithValues: Control.allCases.map { ($0, profile.defaultAction(for: $0)) })
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
    private var mappingsByProductID: [Int: [Control: Action]] = [:]
    private var lastButtonValues: [InputKey: Bool] = [:]
    private var lastHatValues: [Int: Int] = [:]
    private var heldButtons: [InputKey: Action] = [:]
    private var connectedControllerCounts: [Int: Int] = [:]
    private(set) var controllerSelection: ControllerSelection = .automatic
    private var lastActionTimes: [Action: Date] = [:]
    private var statusSound: NSSound?
    private let actionCooldown: TimeInterval = 0.18

    init() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        loadControllerSelection()
        loadSavedMappings()
    }

    func start() {
        let matching = controllerProfiles.keys.sorted().map { productID in
            [
                kIOHIDVendorIDKey as String: nintendoVendorID,
                kIOHIDProductIDKey as String: productID
            ]
        }

        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

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

    func action(for control: Control, profile: ControllerProfile? = nil) -> Action {
        if control == .zr {
            return .lockUnlock
        }
        let resolvedProfile = profile ?? preferredProfile
        return mappingsByProductID[resolvedProfile.productID]?[control]
            ?? resolvedProfile.defaultAction(for: control)
    }

    func displayName(for control: Control) -> String {
        preferredProfile.controlNames[control] ?? control.displayName
    }

    var statusLabel: String {
        switch controllerSelection {
        case .automatic:
            let profiles = activeConnectedProfiles
            if profiles.count > 1 {
                return "PAD"
            }
            return profiles.first?.statusLabel ?? "PAD"
        case .snes, .joyConRight:
            return preferredProfile.statusLabel
        }
    }

    var waitingDescription: String {
        switch controllerSelection {
        case .automatic:
            return "a supported controller"
        case .snes, .joyConRight:
            return controllerSelection.displayName
        }
    }

    func setControllerSelection(_ selection: ControllerSelection) {
        guard selection != controllerSelection else { return }
        releaseHeldButtons()
        lastButtonValues.removeAll()
        lastHatValues.removeAll()
        lastActionTimes.removeAll()
        controllerSelection = selection
        UserDefaults.standard.set(selection.rawValue, forKey: controllerSelectionStorageKey)
        notifyConnectionChanged()
        delegate?.mapperDidTrigger("Controller mode: \(selection.displayName)")
    }

    func setAction(_ action: Action, for control: Control) {
        guard control.isConfigurable, control.choices.contains(action) else { return }
        releaseHeldButtons()
        let profile = preferredProfile
        mappingsByProductID[profile.productID, default: .defaultMappings(for: profile)][control] = action
        UserDefaults.standard.set(action.rawValue, forKey: control.storageKey(productID: profile.productID))
        if profile.productID == snesProductID {
            UserDefaults.standard.set(action.rawValue, forKey: control.legacyStorageKey)
        }
        delegate?.mapperMappingsChanged()
        delegate?.mapperDidTrigger("\(displayName(for: control)) → \(action.displayName)")
    }

    func loadDefaultPreset() {
        releaseHeldButtons()
        let profile = preferredProfile
        mappingsByProductID[profile.productID] = .defaultMappings(for: profile)
        for control in Control.allCases where control.isConfigurable {
            let action = profile.defaultAction(for: control)
            UserDefaults.standard.set(action.rawValue, forKey: control.storageKey(productID: profile.productID))
            if profile.productID == snesProductID {
                UserDefaults.standard.set(action.rawValue, forKey: control.legacyStorageKey)
            }
        }
        lastActionTimes.removeAll()
        delegate?.mapperMappingsChanged()
        if isEnabled {
            delegate?.mapperEnabledChanged(enabled: true)
        } else {
            isEnabled = true
        }
        delegate?.mapperDidTrigger("Loaded \(defaultPresetName) for \(profile.name)")
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
        mappingsByProductID.removeAll()
        for profile in controllerProfiles.values {
            var profileMappings = [Control: Action].defaultMappings(for: profile)
            for control in Control.allCases where control.isConfigurable {
                let profileKey = control.storageKey(productID: profile.productID)
                let rawValue = UserDefaults.standard.string(forKey: profileKey)
                    ?? (profile.productID == snesProductID
                        ? UserDefaults.standard.string(forKey: control.legacyStorageKey)
                        : nil)
                guard let rawValue,
                      let action = Action(rawValue: rawValue),
                      control.choices.contains(action) else {
                    continue
                }
                profileMappings[control] = action
            }
            mappingsByProductID[profile.productID] = profileMappings
        }
    }

    private func loadControllerSelection() {
        guard let rawValue = UserDefaults.standard.string(forKey: controllerSelectionStorageKey),
              let selection = ControllerSelection(rawValue: rawValue) else {
            controllerSelection = .automatic
            return
        }
        controllerSelection = selection
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        guard let profile = controllerProfile(for: device) else { return }
        connectedControllerCounts[profile.productID, default: 0] += 1
        notifyConnectionChanged()
        delegate?.mapperDidTrigger("Connected: \(profile.name)")
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        guard let profile = controllerProfile(for: device) else { return }
        clearInputState(for: deviceIdentifier(device))
        let remaining = max(0, connectedControllerCounts[profile.productID, default: 0] - 1)
        connectedControllerCounts[profile.productID] = remaining
        releaseHeldButtons()
        notifyConnectionChanged()
        delegate?.mapperDidTrigger("Disconnected: \(profile.name)")
    }

    private func notifyConnectionChanged() {
        let products = activeConnectedProfiles.map(\.name)
        delegate?.mapperConnectionChanged(
            connected: !products.isEmpty,
            product: products.isEmpty ? nil : products.joined(separator: " + ")
        )
    }

    private var preferredProfile: ControllerProfile {
        if let selectedProductID = controllerSelection.productID,
           let selectedProfile = controllerProfiles[selectedProductID] {
            return selectedProfile
        }
        if let connectedProfile = activeConnectedProfiles.first {
            return connectedProfile
        }
        return snesProfile
    }

    private var activeConnectedProfiles: [ControllerProfile] {
        controllerProfiles.values
            .filter {
                controllerSelection.accepts($0)
                    && connectedControllerCounts[$0.productID, default: 0] > 0
            }
            .sorted { $0.productID < $1.productID }
    }

    private func controllerProfile(for device: IOHIDDevice) -> ControllerProfile? {
        guard let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber else {
            return nil
        }
        return controllerProfiles[productID.intValue]
    }

    private func deviceIdentifier(_ device: IOHIDDevice) -> Int {
        if let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber {
            return locationID.intValue
        }
        if let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber {
            return productID.intValue
        }
        return 0
    }

    private func clearInputState(for deviceID: Int) {
        lastButtonValues = lastButtonValues.filter { $0.key.deviceID != deviceID }
        lastHatValues.removeValue(forKey: deviceID)
    }

    private func inputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let profile = controllerProfile(for: device) else { return }
        guard controllerSelection.accepts(profile) else { return }
        let deviceID = deviceIdentifier(device)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        if usagePage == kHIDPage_GenericDesktop, usage == 0x39 {
            handleHatSwitch(
                IOHIDValueGetIntegerValue(value),
                deviceID: deviceID,
                profile: profile
            )
            return
        }

        guard usagePage == kHIDPage_Button else { return }

        let inputKey = InputKey(deviceID: deviceID, usage: usage)
        let isPressed = IOHIDValueGetIntegerValue(value) != 0
        let wasPressed = lastButtonValues[inputKey] ?? false
        lastButtonValues[inputKey] = isPressed

        guard isPressed != wasPressed else { return }

        if isPressed, usage == profile.lockButtonUsage {
            isEnabled.toggle()
            return
        }

        guard isEnabled, let control = profile.buttonControls[usage] else { return }

        let action = action(for: control, profile: profile)
        guard action != .none else { return }

        if action.isHoldAction {
            if isPressed {
                beginHold(input: inputKey, action: action)
            } else {
                endHold(input: inputKey)
            }
        } else if isPressed {
            trigger(action)
        }
    }

    private func handleHatSwitch(
        _ rawValue: CFIndex,
        deviceID: Int,
        profile: ControllerProfile
    ) {
        let value = Int(rawValue)
        guard value != lastHatValues[deviceID] else { return }
        lastHatValues[deviceID] = value

        guard isEnabled, let control = profile.hatControls[value] else { return }
        trigger(action(for: control, profile: profile))
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
        case .expandBrowserContentPanel:
            focusThenPost(KeyStroke(keyCode: 6, flags: [.maskControl, .maskCommand]))
        case .previousChat:
            focusThenPost(KeyStroke(keyCode: 33, flags: [.maskShift, .maskCommand]))
        case .nextChat:
            focusThenPost(KeyStroke(keyCode: 30, flags: [.maskShift, .maskCommand]))
        case .toggleSidebar:
            focusThenPost(KeyStroke(keyCode: 11, flags: [.maskCommand]))
        case .toggleSidePanel:
            focusThenPost(KeyStroke(keyCode: 11, flags: [.maskAlternate, .maskCommand]))
        case .newChat:
            focusThenPost(KeyStroke(keyCode: 45, flags: [.maskCommand]))
        case .newTab:
            focusThenPost(KeyStroke(keyCode: 17, flags: [.maskCommand]))
        case .lockUnlock:
            isEnabled.toggle()
        }
    }

    private func beginHold(input: InputKey, action: Action) {
        guard heldButtons[input] == nil else { return }
        heldButtons[input] = action
        delegate?.mapperDidTrigger("\(action.displayName) down")
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        postHoldAction(action, keyDown: true)
    }

    private func endHold(input: InputKey) {
        guard let action = heldButtons.removeValue(forKey: input) else { return }
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
        statusSound?.stop()
        statusSound = NSSound(named: soundName)
        statusSound?.volume = 1.0
        statusSound?.play()
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
        menu.addItem(makeControllerSelectionMenuItem())
        menu.addItem(enabledMenuItem)
        menu.addItem(loadDefaultPresetItem)
        menu.addItem(makeMappingsMenuItem())
        menu.addItem(focusItem)
        menu.addItem(requestPermissionItem)
        menu.addItem(openAccessibilityItem)
        menu.addItem(.separator())
        menu.addItem(disabledItem("Current Map"))
        for control in Control.menuOrder {
            menu.addItem(disabledItem("\(mapper.displayName(for: control)): \(mapper.action(for: control).menuTitle)"))
        }
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.toolTip = "ChatGPT Controller Mapper"
    }

    private func makeControllerSelectionMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Controller Mode: \(mapper.controllerSelection.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: "Controller Mode")

        for selection in ControllerSelection.allCases {
            let selectionItem = NSMenuItem(
                title: selection.displayName,
                action: #selector(selectControllerMode(_:)),
                keyEquivalent: ""
            )
            selectionItem.target = self
            selectionItem.representedObject = selection.rawValue
            selectionItem.state = selection == mapper.controllerSelection ? .on : .off
            submenu.addItem(selectionItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeMappingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Mappings", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Mappings")

        for control in Control.menuOrder {
            let currentAction = mapper.action(for: control)
            let controlName = mapper.displayName(for: control)
            let controlItem = NSMenuItem(title: "\(controlName): \(currentAction.menuTitle)", action: nil, keyEquivalent: "")

            if control.isConfigurable {
                let controlMenu = NSMenu(title: controlName)
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
        let controllerLabel = mapper.statusLabel

        guard mapper.isEnabled else {
            statusItem.button?.title = "\(controllerLabel) Off"
            if let connectedProduct, isConnected {
                statusMenuItem.title = "Controller: \(connectedProduct) (locked)"
            } else {
                statusMenuItem.title = "Controller: waiting for \(mapper.waitingDescription) (locked)"
            }
            return
        }

        let permissionMarker = mapper.hasKeyboardPermission ? "" : "!"
        statusItem.button?.title = isConnected ? "\(controllerLabel)\(permissionMarker)" : "PAD?"
        if let connectedProduct, isConnected {
            statusMenuItem.title = "Controller: \(connectedProduct)"
        } else {
            statusMenuItem.title = "Controller: waiting for \(mapper.waitingDescription)"
        }
    }

    private func updatePermissionTitle() {
        keyboardMenuItem.title = mapper.hasKeyboardPermission ? "Keyboard control: allowed" : "Keyboard control: blocked"
        updateStatusTitle()
    }

    func mapperConnectionChanged(connected: Bool, product: String?) {
        isConnected = connected
        connectedProduct = product
        buildMenu()
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

    @objc private func selectControllerMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selection = ControllerSelection(rawValue: rawValue) else {
            return
        }
        mapper.setControllerSelection(selection)
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
        mapper.requestKeyboardPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--check-accessibility") {
    let trusted = AXIsProcessTrusted()
    print(trusted ? "Accessibility: allowed" : "Accessibility: blocked")
    exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.contains("--print-default-mappings") {
    printDefaultMappingsAndExit()
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
