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
private let modifierReleaseSuppressionInterval: TimeInterval = 0.5

private enum Mode {
    case normal
    case monitor
}

private enum Action: String {
    case focusChatGPT = "focus ChatGPT"
    case toggleVoiceChat = "toggle Voice Chat"
    case toggleVoiceMic = "toggle Voice Chat microphone"
    case closeTabOrWindow = "close current tab/window"
    case expandBrowserContentPanel = "expand browser/content panel"
    case dictation = "dictation"
    case send = "send"
    case clearInput = "clear input"
    case previousChat = "previous chat"
    case nextChat = "next chat"
    case pageUp = "page up"
    case pageDown = "page down"
    case toggleSidebar = "toggle sidebar"
    case toggleSidePanel = "toggle side panel"
    case newChat = "new chat"
    case newTab = "new tab"
}

private struct KeyStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

private struct InputKey: Hashable {
    let deviceID: Int
    let usage: UInt32
}

private struct ControllerProfile {
    let productID: Int
    let name: String
    let buttonActions: [UInt32: Action]
    let heldButtonStrokes: [UInt32: KeyStroke]
    let lockButtonUsage: UInt32
    let hatActions: [Int: Action]
    let buttonModifierUsage: UInt32?
    let modifiedButtonActions: [UInt32: Action]
}

private let snesProfile = ControllerProfile(
    productID: snesProductID,
    name: "Nintendo SNES Controller",
    buttonActions: [
        1: .send,            // B
        3: .clearInput,      // Y
        4: .toggleVoiceChat, // X
        5: .toggleVoiceMic,  // L
        6: .toggleVoiceMic,  // R
        7: .newChat,         // ZL
        9: .focusChatGPT,    // Select / Back
        10: .focusChatGPT    // Start
    ],
    heldButtonStrokes: [
        2: KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]) // A
    ],
    lockButtonUsage: 16, // ZR
    hatActions: [
        0: .previousChat,
        2: .toggleSidePanel,
        4: .nextChat,
        6: .toggleSidebar
    ],
    buttonModifierUsage: nil,
    modifiedButtonActions: [:]
)

// Hardware-calibrated on a Nintendo Switch Joy-Con (R) connected over
// Bluetooth to macOS. The Joy-Con's vertical stick orientation rotates the
// hat values 90 degrees from the SNES controller.
private let joyConRightProfile = ControllerProfile(
    productID: joyConRightProductID,
    name: "Nintendo Switch Joy-Con (R)",
    buttonActions: [
        3: .send,            // B
        2: .toggleVoiceChat, // X
        4: .clearInput,      // Y
        5: .closeTabOrWindow, // SL
        6: .expandBrowserContentPanel, // SR
        15: .toggleVoiceMic,            // R
        10: .newChat,                   // +
        13: .focusChatGPT    // Home
    ],
    heldButtonStrokes: [
        1: KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]) // A
    ],
    lockButtonUsage: 16, // ZR
    hatActions: [
        2: .previousChat,
        4: .toggleSidePanel,
        6: .nextChat,
        0: .toggleSidebar
    ],
    buttonModifierUsage: 12, // Stick click
    modifiedButtonActions: [
        15: .pageDown, // R
        16: .pageUp    // ZR
    ]
)

private let controllerProfiles: [Int: ControllerProfile] = [
    snesProfile.productID: snesProfile,
    joyConRightProfile.productID: joyConRightProfile
]

private func printDefaultMappingsAndExit() -> Never {
    for profile in controllerProfiles.values.sorted(by: { $0.productID < $1.productID }) {
        for (usage, action) in profile.buttonActions.sorted(by: { $0.key < $1.key }) {
            print("\(profile.productID).button.\(usage)=\(action.rawValue)")
        }
        for usage in profile.heldButtonStrokes.keys.sorted() {
            print("\(profile.productID).button.\(usage)=hold dictation")
        }
        print("\(profile.productID).button.\(profile.lockButtonUsage)=lock/unlock mapper")
        for (value, action) in profile.hatActions.sorted(by: { $0.key < $1.key }) {
            print("\(profile.productID).hat.\(value)=\(action.rawValue)")
        }
        if let modifierUsage = profile.buttonModifierUsage {
            for (usage, action) in profile.modifiedButtonActions.sorted(by: { $0.key < $1.key }) {
                print("\(profile.productID).chord.\(modifierUsage)+button.\(usage)=\(action.rawValue)")
            }
            print("\(profile.productID).modifier.\(modifierUsage).hat=suppressed")
            print("\(profile.productID).modifier.\(modifierUsage).hatReleaseSuppression=0.5s")
        }
    }
    exit(EXIT_SUCCESS)
}

private final class Mapper {
    private let mode: Mode
    private let manager: IOHIDManager
    private var lastButtonValues: [InputKey: Bool] = [:]
    private var lastHatValues: [Int: Int] = [:]
    private var hatSuppressionUntilByDeviceID: [Int: Date] = [:]
    private var heldButtons: [InputKey: KeyStroke] = [:]
    private var lastActionTimes: [Action: Date] = [:]
    private var statusSound: NSSound?
    private let actionCooldown: TimeInterval = 0.18
    private var isEnabled = true

    init(mode: Mode) {
        self.mode = mode
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func run() {
        let productIDs = controllerProfiles.keys.sorted()
        let matching = productIDs.map { productID in
            [
                kIOHIDVendorIDKey as String: nintendoVendorID,
                kIOHIDProductIDKey as String: productID
            ]
        }

        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let mapper = Unmanaged<Mapper>.fromOpaque(context).takeUnretainedValue()
            mapper.deviceConnected(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let mapper = Unmanaged<Mapper>.fromOpaque(context).takeUnretainedValue()
            mapper.deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let mapper = Unmanaged<Mapper>.fromOpaque(context).takeUnretainedValue()
            mapper.inputValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            fputs("Could not open HID manager: \(result)\n", stderr)
            exit(1)
        }

        if mode == .normal {
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
        }

        print("ChatGPT controller mapper running.")
        print("SNES Controller: \(String(format: "0x%04X", nintendoVendorID)):\(String(format: "0x%04X", snesProductID))")
        print("Joy-Con (R): \(String(format: "0x%04X", nintendoVendorID)):\(String(format: "0x%04X", joyConRightProductID))")
        switch mode {
        case .normal:
            print("Start/Select: focus ChatGPT")
            print("X/Y: start/stop Voice Chat")
            print("L/R: toggle Voice Chat microphone shortcut (^⌥⌘M)")
            print("ZL: start a new chat")
            print("ZR: lock/unlock mapper")
            print("D-pad Up/Down: previous/next chat")
            print("D-pad Left: toggle sidebar")
            print("D-pad Right: toggle side panel")
            print("A: hold ChatGPT dictation shortcut")
            print("Y: clear input")
            print("B: send message")
        case .monitor:
            print("Monitor mode. Press SNES or Joy-Con controls; this will print input events.")
        }
        fflush(stdout)

        CFRunLoopRun()
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        print("Connected: \(product)")
        fflush(stdout)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        clearInputState(for: deviceIdentifier(device))
        releaseHeldButtons()
        print("Removed: \(product)")
        fflush(stdout)
    }

    private func inputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let profile = controllerProfile(for: device) else { return }
        let deviceID = deviceIdentifier(device)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        if usagePage == kHIDPage_GenericDesktop, usage == 0x39 {
            if mode == .monitor {
                print("\(profile.name) hat value=\(integerValue)")
                fflush(stdout)
            } else {
                handleHatSwitch(integerValue, deviceID: deviceID, profile: profile)
            }
            return
        }

        if usagePage == kHIDPage_Button {
            let inputKey = InputKey(deviceID: deviceID, usage: usage)
            let isPressed = integerValue != 0
            let wasPressed = lastButtonValues[inputKey] ?? false
            lastButtonValues[inputKey] = isPressed

            if isPressed != wasPressed {
                if !isPressed,
                   let modifierUsage = profile.buttonModifierUsage,
                   usage == modifierUsage {
                    hatSuppressionUntilByDeviceID[deviceID] = Date().addingTimeInterval(
                        modifierReleaseSuppressionInterval
                    )
                }
                if mode == .monitor {
                    print("\(profile.name) button usage=\(usage) \(isPressed ? "down" : "up")")
                    fflush(stdout)
                } else if isEnabled,
                          isPressed,
                          let modifierUsage = profile.buttonModifierUsage,
                          lastButtonValues[InputKey(deviceID: deviceID, usage: modifierUsage)] == true,
                          let modifiedAction = profile.modifiedButtonActions[usage] {
                    trigger(modifiedAction)
                } else if isPressed, usage == profile.lockButtonUsage {
                    toggleEnabled()
                } else if !isEnabled {
                    return
                } else if isPressed,
                          let modifierUsage = profile.buttonModifierUsage,
                          usage == modifierUsage {
                    print("Action: focus ChatGPT for scroll mode")
                    fflush(stdout)
                    focusChatGPT()
                } else if let stroke = profile.heldButtonStrokes[usage] {
                    if isPressed {
                        beginHold(input: inputKey, stroke: stroke)
                    } else {
                        endHold(input: inputKey, stroke: stroke)
                    }
                } else if isPressed, let action = profile.buttonActions[usage] {
                    trigger(action)
                }
            }
            return
        }

        if mode == .monitor, usagePage == kHIDPage_GenericDesktop {
            print("generic usage=\(usage) value=\(integerValue)")
            fflush(stdout)
        }
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
        hatSuppressionUntilByDeviceID.removeValue(forKey: deviceID)
    }

    private func handleHatSwitch(
        _ rawValue: CFIndex,
        deviceID: Int,
        profile: ControllerProfile
    ) {
        let value = Int(rawValue)
        guard value != lastHatValues[deviceID] else { return }
        lastHatValues[deviceID] = value
        guard isEnabled else { return }
        if let modifierUsage = profile.buttonModifierUsage,
           lastButtonValues[InputKey(deviceID: deviceID, usage: modifierUsage)] == true {
            return
        }
        if let suppressionUntil = hatSuppressionUntilByDeviceID[deviceID] {
            if Date() < suppressionUntil {
                return
            }
            hatSuppressionUntilByDeviceID.removeValue(forKey: deviceID)
        }
        guard let action = profile.hatActions[value] else { return }
        trigger(action)
    }

    private func trigger(_ action: Action) {
        let now = Date()
        if let last = lastActionTimes[action], now.timeIntervalSince(last) < actionCooldown {
            return
        }
        lastActionTimes[action] = now

        print("Action: \(action.rawValue)")
        fflush(stdout)

        switch action {
        case .focusChatGPT:
            focusChatGPT()
        case .toggleVoiceChat:
            // ChatGPT default: Toggle voice chat = Control + Shift + V.
            focusThenPost(KeyStroke(keyCode: 9, flags: [.maskControl, .maskShift]))
        case .toggleVoiceMic:
            // Assign this in ChatGPT Keyboard Shortcuts to:
            // Toggle Voice Chat microphone = Control + Option + Command + M
            focusThenPost(KeyStroke(keyCode: 46, flags: [.maskControl, .maskAlternate, .maskCommand]))
        case .closeTabOrWindow:
            focusThenPost(KeyStroke(keyCode: 13, flags: [.maskCommand]))
        case .expandBrowserContentPanel:
            // Ryan's custom shortcut for expanding the browser/content panel.
            focusThenPost(KeyStroke(keyCode: 6, flags: [.maskControl, .maskCommand]))
        case .dictation:
            focusThenPost(KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]))
        case .send:
            focusThenPost(KeyStroke(keyCode: 36, flags: []))
        case .clearInput:
            clearInput()
        case .previousChat:
            focusThenPost(KeyStroke(keyCode: 33, flags: [.maskShift, .maskCommand]))
        case .nextChat:
            focusThenPost(KeyStroke(keyCode: 30, flags: [.maskShift, .maskCommand]))
        case .pageUp:
            focusThenPost(KeyStroke(keyCode: 116, flags: []))
        case .pageDown:
            focusThenPost(KeyStroke(keyCode: 121, flags: []))
        case .toggleSidebar:
            focusThenPost(KeyStroke(keyCode: 11, flags: [.maskCommand]))
        case .toggleSidePanel:
            focusThenPost(KeyStroke(keyCode: 11, flags: [.maskAlternate, .maskCommand]))
        case .newChat:
            focusThenPost(KeyStroke(keyCode: 45, flags: [.maskCommand]))
        case .newTab:
            focusThenPost(KeyStroke(keyCode: 17, flags: [.maskCommand]))
        }
    }

    private func beginHold(input: InputKey, stroke: KeyStroke) {
        guard heldButtons[input] == nil else { return }
        heldButtons[input] = stroke
        print("Action: hold dictation down")
        fflush(stdout)
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        postKeyDown(stroke)
    }

    private func endHold(input: InputKey, stroke: KeyStroke) {
        guard heldButtons.removeValue(forKey: input) != nil else { return }
        print("Action: hold dictation up")
        fflush(stdout)
        postKeyUp(stroke)
    }

    private func toggleEnabled() {
        isEnabled.toggle()
        if !isEnabled {
            releaseHeldButtons()
        }
        playStatusSound(enabled: isEnabled)
        print(isEnabled ? "Mapper unlocked." : "Mapper locked.")
        fflush(stdout)
    }

    private func releaseHeldButtons() {
        for stroke in heldButtons.values {
            postKeyUp(stroke)
        }
        heldButtons.removeAll()
    }

    private func playStatusSound(enabled: Bool) {
        let soundName = NSSound.Name(enabled ? "Tink" : "Basso")
        statusSound?.stop()
        statusSound = NSSound(named: soundName)
        statusSound?.volume = 1.0
        statusSound?.play()
    }

    private func focusChatGPT() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: chatGPTBundleID).first {
            app.activate(options: [.activateAllWindows])
            return
        }

        let url = URL(fileURLWithPath: chatGPTPath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error {
                fputs("Could not open ChatGPT: \(error.localizedDescription)\n", stderr)
            } else {
                app?.activate(options: [.activateAllWindows])
            }
        }
    }

    private func focusThenPost(_ stroke: KeyStroke) {
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        post(stroke)
    }

    private func clearInput() {
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        post(KeyStroke(keyCode: 0, flags: [.maskCommand]))
        usleep(50_000)
        post(KeyStroke(keyCode: 51, flags: []))
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
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            fputs("Could not create CGEventSource.\n", stderr)
            return
        }

        let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: keyDown)
        guard let event else { return }
        event.flags = stroke.flags
        event.post(tap: .cghidEventTap)
    }
}

private func printUsageAndExit() -> Never {
    print("""
    Usage:
      chatgpt-snes-mapper             Run the ChatGPT controller mapper
      chatgpt-snes-mapper --monitor   Print SNES and Joy-Con input events
      chatgpt-snes-mapper --print-default-mappings
                                      Print defaults without opening a HID device

    Default map:
      Start / Select -> focus ChatGPT
      X              -> Control + Shift + V
      Y              -> Command + A, Delete
      L / R          -> Control + Option + Command + M
      ZL             -> Command + N
      ZR             -> lock/unlock mapper
      D-pad Up       -> Shift + Command + [
      D-pad Down     -> Shift + Command + ]
      D-pad Left     -> Command + B
      D-pad Right    -> Option + Command + B
      A              -> hold Control + Shift + D
      B              -> Return

    Joy-Con map:
      +             -> Command + N
      Home          -> focus ChatGPT
      A             -> hold Control + Shift + D
      B             -> Return
      X             -> Control + Shift + V
      Y             -> Command + A, Delete
      SL            -> Command + W
      SR            -> Control + Command + Z
      R             -> Control + Option + Command + M
      ZR            -> lock/unlock mapper
      Stick Up/Down -> previous/next chat
      Stick Left    -> Command + B
      Stick Right   -> Option + Command + B
      Stick Click        -> focus ChatGPT for scroll mode
      Stick Click + R    -> Page Down
      Stick Click + ZR   -> Page Up
      Stick Click + Stick direction -> no action
      Stick directions remain blocked for 0.5 seconds after releasing Stick Click

    Required ChatGPT shortcuts:
      Toggle Voice Chat Microphone        -> Control + Option + Command + M
      Browser/content side-panel expansion -> Control + Command + Z
      Joy-Con R requires the microphone shortcut; SR requires the panel shortcut.

    Default preset: \(defaultPresetName)
    """)
    exit(0)
}

private let args = CommandLine.arguments.dropFirst()
private let mode: Mode

if args.isEmpty {
    mode = .normal
} else if args.count == 1, args.first == "--monitor" {
    mode = .monitor
} else if args.count == 1, args.first == "--print-default-mappings" {
    printDefaultMappingsAndExit()
} else if args.count == 1, ["--help", "-h"].contains(args.first!) {
    printUsageAndExit()
} else {
    printUsageAndExit()
}

Mapper(mode: mode).run()
