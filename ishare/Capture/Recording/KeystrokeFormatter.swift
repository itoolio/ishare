import Carbon.HIToolbox
import Foundation

struct KeystrokeModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let control = KeystrokeModifiers(rawValue: 1 << 0)
    static let option = KeystrokeModifiers(rawValue: 1 << 1)
    static let shift = KeystrokeModifiers(rawValue: 1 << 2)
    static let command = KeystrokeModifiers(rawValue: 1 << 3)

    static let shortcutModifiers: KeystrokeModifiers = [.control, .option, .command]

    var symbols: String {
        [(KeystrokeModifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }
            .map(\.1)
            .joined()
    }
}

struct Keystroke: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case typed
        case shortcut
    }

    let text: String
    let kind: Kind
}

enum KeystrokeFormatter {
    static func keystroke(keyCode: Int, characters: String?, baseCharacters: String?, modifiers: KeystrokeModifiers, shortcutsOnly: Bool) -> Keystroke? {
        let special = specialKeyName(for: keyCode)
        let usesShortcutModifier = !modifiers.isDisjoint(with: .shortcutModifiers)

        if !usesShortcutModifier, keyCode == kVK_Space {
            return shortcutsOnly ? nil : Keystroke(text: " ", kind: .typed)
        }
        if !usesShortcutModifier, special == nil, let typed = printable(characters) {
            return shortcutsOnly ? nil : Keystroke(text: typed, kind: .typed)
        }

        guard let key = special ?? printable(baseCharacters)?.uppercased() else { return nil }
        let standsAlone = isStandaloneKey(keyCode)
        if shortcutsOnly, !usesShortcutModifier, !standsAlone {
            return nil
        }
        return Keystroke(text: modifiers.symbols + key, kind: .shortcut)
    }

    static func specialKeyName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_Return: "↩"
        case kVK_ANSI_KeypadEnter: "⌤"
        case kVK_Tab: "⇥"
        case kVK_Space: "Space"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_Escape: "⎋"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Home: "↖"
        case kVK_End: "↘"
        case kVK_PageUp: "⇞"
        case kVK_PageDown: "⇟"
        default: functionKeyName(for: keyCode)
        }
    }

    private static let functionKeyCodes = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static func functionKeyName(for keyCode: Int) -> String? {
        functionKeyCodes.firstIndex(of: keyCode).map { "F\($0 + 1)" }
    }

    private static func isStandaloneKey(_ keyCode: Int) -> Bool {
        keyCode == kVK_Escape || functionKeyCodes.contains(keyCode)
    }

    private static func printable(_ characters: String?) -> String? {
        guard let characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700 ... 0xF8FF).contains($0.value) })
        else { return nil }
        return characters
    }
}

struct KeystrokeTicker: Equatable, Sendable {
    static let joinInterval: TimeInterval = 1.2
    static let maximumTypedLength = 28

    private(set) var text = ""
    private(set) var lastKeystroke: Keystroke?
    private(set) var lastDate: Date?
    private var repeatCount = 1

    mutating func register(_ keystroke: Keystroke, at date: Date) {
        let isRecent = lastDate.map { date.timeIntervalSince($0) <= Self.joinInterval } ?? false
        defer {
            lastKeystroke = keystroke
            lastDate = date
        }

        if isRecent, keystroke.kind == .typed, lastKeystroke?.kind == .typed {
            text = String((text + keystroke.text).suffix(Self.maximumTypedLength))
            return
        }
        if isRecent, keystroke.kind == .shortcut, keystroke == lastKeystroke {
            repeatCount += 1
            text = "\(keystroke.text) ×\(repeatCount)"
            return
        }
        repeatCount = 1
        text = keystroke.text
    }

    func isExpired(at date: Date, after interval: TimeInterval) -> Bool {
        guard let lastDate else { return true }
        return date.timeIntervalSince(lastDate) > interval
    }
}
