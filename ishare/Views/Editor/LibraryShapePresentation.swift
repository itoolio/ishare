import ishareCore

extension LibraryShape {
    var title: String {
        switch self {
        case .roundBubble: "Speech Bubble".localized()
        case .thoughtBubble: "Thought Bubble".localized()
        case .bracketLeft: "Left Bracket".localized()
        case .bracketRight: "Right Bracket".localized()
        case .braceLeft: "Left Brace".localized()
        case .braceRight: "Right Brace".localized()
        case .check: "Check Mark".localized()
        case .cross: "Cross Mark".localized()
        case .keycap: "Key Cap".localized()
        }
    }

    var symbol: String {
        switch self {
        case .roundBubble: "bubble.left"
        case .thoughtBubble: "cloud"
        case .bracketLeft: "chevron.left.square"
        case .bracketRight: "chevron.right.square"
        case .braceLeft: "curlybraces"
        case .braceRight: "curlybraces.square"
        case .check: "checkmark"
        case .cross: "xmark"
        case .keycap: "command.square"
        }
    }
}
