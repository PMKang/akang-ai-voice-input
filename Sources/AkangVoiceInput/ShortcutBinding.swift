import AppKit
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt

    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let shift = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: Self = []
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.command) { value.insert(.command) }
        self = value
    }

    var displayPrefix: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined(separator: " ")
    }
}

struct ShortcutValidation: Equatable {
    enum Kind: Equatable {
        case valid
        case warning
        case invalid
    }

    let kind: Kind
    let message: String

    var canUse: Bool { kind != .invalid }

    static func valid(_ message: String = "此快捷键可以使用") -> Self {
        Self(kind: .valid, message: message)
    }

    static func warning(_ message: String) -> Self {
        Self(kind: .warning, message: "可以使用。\(message)")
    }

    static func invalid(_ message: String) -> Self {
        Self(kind: .invalid, message: message)
    }
}

struct CustomShortcutBinding: Codable, Equatable, Hashable {
    let modifiers: ShortcutModifiers
    let keyCode: UInt16

    static let capsLockKeyCode: UInt16 = 57
    static let escapeKeyCode: UInt16 = 53
    static let backspaceKeyCode: UInt16 = 51

    var displayText: String {
        [modifiers.displayPrefix, Self.keyName(for: keyCode)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var validation: ShortcutValidation {
        if keyCode == Self.capsLockKeyCode {
            return .invalid("Caps Lock 由系统管理，不能作为全局快捷键。")
        }
        guard Self.supportedKeyCodes.contains(keyCode) else {
            return .invalid("请选择字母、数字、空格或 F2–F12 功能键。")
        }

        if Self.functionKeyCodes.contains(keyCode) {
            if modifiers.isEmpty {
                return .warning("部分键盘会把功能键用于亮度或音量；实际效果取决于系统键盘设置。")
            }
            return knownConflict ?? .valid()
        }

        if modifiers.isEmpty {
            return .invalid("为避免影响正常打字，字母、数字和空格不能单独使用。")
        }
        if let knownConflict {
            return knownConflict
        }
        if modifiers == .shift {
            return .invalid("仅使用 Shift 仍会影响正常输入，请加入 Control、Option 或 Command。")
        }

        return possibleConflictWarning ?? .valid()
    }

    private var knownConflict: ShortcutValidation? {
        if keyCode == 49 {
            if modifiers == .command || modifiers == [.command, .option] {
                return .invalid("这个组合键通常由 Spotlight 或 Finder 使用，请换一个快捷键。")
            }
            if modifiers == .control
                || modifiers == [.control, .option]
                || modifiers == [.control, .shift] {
                return .invalid("这个组合键通常用于切换输入法，请换一个快捷键。")
            }
            if modifiers == [.control, .command] {
                return .invalid("这个组合键通常用于打开字符检视器，请换一个快捷键。")
            }
        }

        if modifiers == [.command, .shift],
           [Self.keyCode(forDigit: 3), Self.keyCode(forDigit: 4), Self.keyCode(forDigit: 5)]
            .compactMap({ $0 })
            .contains(keyCode) {
            return .invalid("这个组合键由 macOS 截图功能使用，请换一个快捷键。")
        }

        if modifiers == [.control, .command], keyCode == 12 {
            return .invalid("⌃ ⌘ Q 由 macOS 锁定屏幕功能使用，请换一个快捷键。")
        }

        if modifiers == [.command, .shift], keyCode == 12 {
            return .invalid("⇧ ⌘ Q 由 macOS 注销功能使用，请换一个快捷键。")
        }

        if modifiers == .command, Self.standardCommandKeyCodes.contains(keyCode) {
            return .invalid("这是常用的 macOS 或应用菜单快捷键，请加入第二个修饰键。")
        }

        return nil
    }

    private var possibleConflictWarning: ShortcutValidation? {
        if modifiers == .command {
            return .warning("这个组合可能与应用菜单冲突，建议优先选择双修饰键。")
        }
        if modifiers == .option {
            return .warning("Option 加字母通常用于输入特殊字符；设为全局快捷键后可能影响该字符输入。")
        }
        if modifiers == .control {
            return .warning("这个组合键可能被当前应用使用；macOS 无法可靠检测所有应用内冲突。")
        }
        if modifiers.contains([.control, .option]) {
            return .warning("开启 VoiceOver 时，Control + Option 组合可能与辅助功能快捷键冲突。")
        }
        if modifiers.contains(.command) {
            return .warning("这个组合可能与某些应用菜单冲突；macOS 无法可靠检测所有应用内快捷键。")
        }
        return nil
    }

    static func keyName(for keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static func keyCode(forDigit digit: Int) -> UInt16? {
        keyNames.first { $0.value == String(digit) }?.key
    }

    private static let letterKeyNames: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G",
        4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S",
        17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z"
    ]

    private static let digitKeyNames: [UInt16: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9"
    ]

    private static let functionKeyNames: [UInt16: String] = [
        120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    private static let keyNames: [UInt16: String] =
        letterKeyNames
        .merging(digitKeyNames) { current, _ in current }
        .merging(functionKeyNames) { current, _ in current }
        .merging([49: "Space"]) { current, _ in current }

    private static let functionKeyCodes = Set(functionKeyNames.keys)
    private static let supportedKeyCodes = Set(keyNames.keys)
    private static let standardCommandKeyCodes: Set<UInt16> = [
        0, 8, 3, 4, 46, 45, 31, 35, 12, 1, 9, 13, 7, 6
    ]
}

struct ShortcutConfiguration: Equatable {
    let choice: ShortcutChoice
    let customBinding: CustomShortcutBinding?

    static let defaultConfiguration = Self(choice: .optionCommand, customBinding: nil)

    var label: String {
        if choice == .custom, let customBinding {
            return customBinding.displayText
        }
        return choice.label
    }

    var requiresInputMonitoring: Bool {
        choice.requiresInputMonitoring
    }

    var requiresAccessibilityControl: Bool {
        choice.requiresAccessibilityControl
    }
}

enum ShortcutPreferenceStore {
    static let choiceKey = "voiceShortcutChoice"
    static let customBindingKey = "voiceCustomShortcutBindingV1"

    static func load(from defaults: UserDefaults = .standard) -> ShortcutConfiguration {
        let choice = defaults.string(forKey: choiceKey)
            .flatMap(ShortcutChoice.init(rawValue:))
            ?? .optionCommand
        guard choice == .custom else {
            return ShortcutConfiguration(choice: choice, customBinding: nil)
        }
        guard let data = defaults.data(forKey: customBindingKey),
              let binding = try? JSONDecoder().decode(CustomShortcutBinding.self, from: data),
              binding.validation.canUse else {
            return .defaultConfiguration
        }
        return ShortcutConfiguration(choice: .custom, customBinding: binding)
    }

    static func save(
        _ configuration: ShortcutConfiguration,
        to defaults: UserDefaults = .standard
    ) throws {
        if configuration.choice == .custom {
            guard let binding = configuration.customBinding, binding.validation.canUse else {
                throw ShortcutRegistrationError("自定义快捷键无效，未保存设置。")
            }
            defaults.set(try JSONEncoder().encode(binding), forKey: customBindingKey)
        }
        defaults.set(configuration.choice.rawValue, forKey: choiceKey)
    }
}

struct ShortcutRegistrationError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
