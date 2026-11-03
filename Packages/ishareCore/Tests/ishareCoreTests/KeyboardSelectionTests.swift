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
