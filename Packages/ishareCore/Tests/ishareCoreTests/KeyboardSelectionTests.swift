import CoreGraphics
import Testing
@testable import ishareCore

struct KeyboardSelectionTests {
    @Test func arrowsThenReturnPlaceBothCornersThenConfirm() {
        var keyboard = KeyboardSelection()
        #expect(keyboard.returnPressed() == .defaultAction)
        keyboard.arrowPressed(hasSelection: false)
        #expect(keyboard.stage == .placingFirstCorner)
        #expect(keyboard.returnPressed() == .setFirstCorner)
        keyboard.arrowPressed(hasSelection: true)
        #expect(keyboard.stage == .placingSecondCorner)
        #expect(keyboard.returnPressed() == .confirm)
        #expect(keyboard.stage == .inactive)
    }

    @Test func escapeStepsBackOneStageAtATime() {
        var keyboard = KeyboardSelection()
        keyboard.arrowPressed(hasSelection: false)
        _ = keyboard.returnPressed()
        #expect(keyboard.escapePressed() == .clearFirstCorner)
        #expect(keyboard.escapePressed() == .leaveKeyboardMode)
        #expect(keyboard.escapePressed() == .defaultAction)
    }

    @Test func usingThePointerLeavesKeyboardMode() {
        var keyboard = KeyboardSelection()
        keyboard.arrowPressed(hasSelection: false)
        keyboard.pointerUsed()
        #expect(keyboard.returnPressed() == .defaultAction)
    }

    @Test func arrowsWithAnExistingSelectionAdjustItsSecondCorner() {
        var keyboard = KeyboardSelection()
        keyboard.arrowPressed(hasSelection: true)
        #expect(keyboard.returnPressed() == .confirm)
    }
}

struct KeyboardCrosshairTests {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

    @Test func followsThePointerUntilTheKeyboardTakesOver() {
        #expect(KeyboardCrosshair.location(stage: .inactive, pointer: CGPoint(x: 5, y: 5), secondCorner: nil, bounds: bounds) == CGPoint(x: 5, y: 5))
        #expect(KeyboardCrosshair.location(stage: .inactive, pointer: nil, secondCorner: nil, bounds: bounds) == nil)
        #expect(KeyboardCrosshair.location(stage: .placingFirstCorner, pointer: nil, secondCorner: nil, bounds: bounds) == CGPoint(x: 100, y: 50))
    }

    @Test func followsTheSecondCornerWhileItMoves() {
        let corner = CGPoint(x: 150, y: 80)
        #expect(KeyboardCrosshair.location(stage: .placingSecondCorner, pointer: CGPoint(x: 5, y: 5), secondCorner: corner, bounds: bounds) == corner)
    }
}
