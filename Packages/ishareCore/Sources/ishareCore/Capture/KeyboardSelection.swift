public struct KeyboardSelection: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case inactive
        case placingFirstCorner
        case placingSecondCorner
    }

    public enum ReturnAction: Equatable, Sendable {
        case setFirstCorner
        case confirm
        case defaultAction
    }

    public enum EscapeAction: Equatable, Sendable {
        case clearFirstCorner
        case leaveKeyboardMode
        case defaultAction
    }

    public private(set) var stage: Stage = .inactive

    public init() {}

    public mutating func arrowPressed(hasSelection: Bool) {
        if stage == .inactive {
            stage = hasSelection ? .placingSecondCorner : .placingFirstCorner
        }
    }

    public mutating func returnPressed() -> ReturnAction {
        switch stage {
        case .inactive:
            return .defaultAction
        case .placingFirstCorner:
            stage = .placingSecondCorner
            return .setFirstCorner
        case .placingSecondCorner:
            stage = .inactive
            return .confirm
        }
    }

    public mutating func escapePressed() -> EscapeAction {
        switch stage {
        case .inactive:
            return .defaultAction
        case .placingFirstCorner:
            stage = .inactive
            return .leaveKeyboardMode
        case .placingSecondCorner:
            stage = .placingFirstCorner
            return .clearFirstCorner
        }
    }

    public mutating func pointerUsed() {
        stage = .inactive
    }
}
