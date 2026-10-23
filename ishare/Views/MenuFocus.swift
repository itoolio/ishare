import SwiftUI

enum MenuFocusTarget: Hashable, Sendable {
    case destination
    case settings
    case donate
    case more
    case capture(Int)
    case record(Int)
    case stopRecording
    case chip(Int)
    case recent(Int)
    case history
    case footer(Int)
}

enum MenuFocusDirection: Sendable {
    case up
    case down
    case left
    case right

    var flipped: MenuFocusDirection {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}

enum MenuFocusNavigator {
    static func position(of target: MenuFocusTarget, in rows: [[MenuFocusTarget]]) -> (row: Int, column: Int)? {
        for (rowIndex, row) in rows.enumerated() {
            if let column = row.firstIndex(of: target) {
                return (rowIndex, column)
            }
        }
        return nil
    }

    static func initialTarget(in rows: [[MenuFocusTarget]]) -> MenuFocusTarget? {
        let targets = rows.flatMap { $0 }
        return targets.contains(.capture(0)) ? .capture(0) : targets.first
    }

    static func move(from current: MenuFocusTarget?, _ direction: MenuFocusDirection, in rows: [[MenuFocusTarget]]) -> MenuFocusTarget? {
        let rows = rows.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return nil }
        guard let current, let position = position(of: current, in: rows) else {
            return initialTarget(in: rows)
        }
        let row = rows[position.row]
        switch direction {
        case .left:
            return row[max(position.column - 1, 0)]
        case .right:
            return row[min(position.column + 1, row.count - 1)]
        case .up, .down:
            let targetRow = direction == .up ? position.row - 1 : position.row + 1
            guard rows.indices.contains(targetRow) else { return current }
            let destination = rows[targetRow]
            return destination[column(for: position.column, from: row.count, to: destination.count)]
        }
    }

    static func column(for column: Int, from sourceCount: Int, to destinationCount: Int) -> Int {
        guard sourceCount > 0, destinationCount > 0 else { return 0 }
        let center = (Double(column) + 0.5) / Double(sourceCount)
        return min(max(Int(center * Double(destinationCount)), 0), destinationCount - 1)
    }

    static func captureIndex(forKey character: Character) -> Int? {
        guard let digit = character.wholeNumberValue, (1 ... 4).contains(digit) else { return nil }
        return digit - 1
    }

    static func isRecentLinksKey(_ character: Character) -> Bool {
        character == "l" || character == "L"
    }
}

enum MenuFocusLayout {
    static func headerRow(showsDonate: Bool) -> [MenuFocusTarget] {
        showsDonate ? [.destination, .donate, .settings, .more] : [.destination, .settings, .more]
    }

    static func rows(sections: [MenuSection], isRecording: Bool, chipCount: Int, recentCount: Int, showsDonate: Bool = false) -> [[MenuFocusTarget]] {
        [headerRow(showsDonate: showsDonate)] + sections.compactMap { section in
            switch section {
            case .capture:
                (0 ..< 4).map(MenuFocusTarget.capture)
            case .record:
                isRecording ? [.stopRecording] : [.record(0), .record(1)]
            case .afterCapture:
                (0 ..< chipCount).map(MenuFocusTarget.chip)
            case .recentUploads:
                recentCount > 0 ? (0 ..< recentCount).map(MenuFocusTarget.recent) + [.history] : nil
            case .footer:
                [.footer(0), .footer(1)]
            }
        }
    }
}

private struct MenuFocusedTargetKey: EnvironmentKey {
    static let defaultValue: MenuFocusTarget? = nil
}

extension EnvironmentValues {
    var menuFocusedTarget: MenuFocusTarget? {
        get { self[MenuFocusedTargetKey.self] }
        set { self[MenuFocusedTargetKey.self] = newValue }
    }
}

enum MenuFocusShape {
    case roundedRectangle(CGFloat)
    case circle
}

private struct MenuFocusRing: ViewModifier {
    let target: MenuFocusTarget
    let shape: MenuFocusShape
    @Environment(\.menuFocusedTarget) private var focused

    func body(content: Content) -> some View {
        content.overlay {
            if focused == target {
                ring
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .accessibilityAddTraits(focused == target ? .isSelected : [])
    }

    @ViewBuilder
    private var ring: some View {
        switch shape {
        case let .roundedRectangle(radius):
            RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                .strokeBorder(Color.menuAccent, lineWidth: 2)
                .padding(-3)
        case .circle:
            Circle()
                .strokeBorder(Color.menuAccent, lineWidth: 2)
                .padding(-3)
        }
    }
}

extension View {
    func menuFocusRing(_ target: MenuFocusTarget, shape: MenuFocusShape = .roundedRectangle(10)) -> some View {
        modifier(MenuFocusRing(target: target, shape: shape))
    }
}
