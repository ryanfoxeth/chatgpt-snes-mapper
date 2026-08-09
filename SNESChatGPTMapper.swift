import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

private let vendorID = 0x057E
private let productID = 0x2017
private let chatGPTBundleID = "com.openai.codex"
private let chatGPTPath = "/Applications/ChatGPT.app"
private let defaultPresetName = "ChatGPT Voice Macropad"

private enum Mode {
    case normal
    case monitor
}

private enum Action: String {
    case focusChatGPT = "focus ChatGPT"
    case toggleVoiceChat = "toggle Voice Chat"
    case toggleVoiceMic = "toggle Voice Chat microphone"
    case dictation = "dictation"
    case send = "send"
    case clearInput = "clear input"
    case previousChat = "previous chat"
    case nextChat = "next chat"
    case toggleSidebar = "toggle sidebar"
    case toggleSidePanel = "toggle side panel"
    case newChat = "new chat"
    case newTab = "new tab"
}

private struct KeyStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

private final class Mapper {
    private let mode: Mode
    private let manager: IOHIDManager
    private var lastButtonValues: [UInt32: Bool] = [:]
    private var lastHatValue = 8
    private var heldButtons: Set<UInt32> = []
    private var lastActionTimes: [Action: Date] = [:]
    private var statusSound: NSSound?
    private let actionCooldown: TimeInterval = 0.18
    private var isEnabled = true
    private let lockToggleButtonUsage: UInt32 = 16

    // Calibrated on this macOS host:
    // B=1, A=2, Y=3, X=4, L=5, R=6, ZL=7, Select=9, Start=10, ZR=16.
    private let buttonActions: [UInt32: Action] = [
        1: .send,            // B
        3: .clearInput,      // Y
        4: .toggleVoiceChat, // X
        5: .toggleVoiceMic,  // L
        6: .toggleVoiceMic,  // R
        7: .newChat,         // ZL
        9: .focusChatGPT,    // Select / Back
        10: .focusChatGPT    // Start
    ]
    private let heldButtonStrokes: [UInt32: KeyStroke] = [
        2: KeyStroke(keyCode: 2, flags: [.maskControl, .maskShift]) // A: hold ChatGPT dictation
    ]

    init(mode: Mode) {
        self.mode = mode
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func run() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

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

        print("SNES ChatGPT mapper running.")
        print("Device: Nintendo SNES Controller \(String(format: "0x%04X", vendorID)):\(String(format: "0x%04X", productID))")
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
            print("Monitor mode. Press SNES buttons; this will print IOHID usages.")
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
        print("Removed: \(product)")
        fflush(stdout)
    }

    private func inputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        if usagePage == kHIDPage_GenericDesktop, usage == 0x39 {
            if mode == .monitor {
                print("hat value=\(integerValue)")
                fflush(stdout)
            } else {
                handleHatSwitch(integerValue)
            }
            return
        }

        if usagePage == kHIDPage_Button {
            let isPressed = integerValue != 0
            let wasPressed = lastButtonValues[usage] ?? false
            lastButtonValues[usage] = isPressed

            if isPressed != wasPressed {
                if mode == .monitor {
                    print("button usage=\(usage) \(isPressed ? "down" : "up")")
                    fflush(stdout)
                } else if isPressed, usage == lockToggleButtonUsage {
                    toggleEnabled()
                } else if !isEnabled {
                    return
                } else if let stroke = heldButtonStrokes[usage] {
                    if isPressed {
                        beginHold(button: usage, stroke: stroke)
                    } else {
                        endHold(button: usage, stroke: stroke)
                    }
                } else if isPressed, let action = buttonActions[usage] {
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

    private func handleHatSwitch(_ rawValue: CFIndex) {
        let value = Int(rawValue)
        guard value != lastHatValue else { return }
        lastHatValue = value
        guard isEnabled else { return }

        switch value {
        case 0:
            trigger(.previousChat)
        case 2:
            trigger(.toggleSidePanel)
        case 4:
            trigger(.nextChat)
        case 6:
            trigger(.toggleSidebar)
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

    private func beginHold(button: UInt32, stroke: KeyStroke) {
        guard !heldButtons.contains(button) else { return }
        heldButtons.insert(button)
        print("Action: hold dictation down")
        fflush(stdout)
        focusChatGPT()
        Thread.sleep(forTimeInterval: 0.08)
        postKeyDown(stroke)
    }

    private func endHold(button: UInt32, stroke: KeyStroke) {
        guard heldButtons.contains(button) else { return }
        heldButtons.remove(button)
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
        for button in heldButtons {
            if let stroke = heldButtonStrokes[button] {
                postKeyUp(stroke)
            }
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
      chatgpt-snes-mapper             Run the ChatGPT SNES controller mapper
      chatgpt-snes-mapper --monitor   Print raw controller button usages

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
} else if args.count == 1, ["--help", "-h"].contains(args.first!) {
    printUsageAndExit()
} else {
    printUsageAndExit()
}

Mapper(mode: mode).run()
