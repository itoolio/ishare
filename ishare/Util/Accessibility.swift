import AppKit
import SwiftUI

enum AccessibilityText {
    static func state(_ isOn: Bool) -> String {
        isOn ? "On".localized() : "Off".localized()
    }
}

enum MotionPreference {
    @MainActor static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func animation(_ animation: Animation, reducesMotion: Bool) -> Animation? {
        reducesMotion ? nil : animation
    }

    static func duration(_ duration: TimeInterval, reducesMotion: Bool) -> TimeInterval {
        reducesMotion ? 0 : duration
    }

    static func transition(_ transition: AnyTransition, reducesMotion: Bool) -> AnyTransition {
        reducesMotion ? .opacity : transition
    }
}

@MainActor
func withMotionAnimation<Result>(_ animation: Animation = .default, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(MotionPreference.animation(animation, reducesMotion: MotionPreference.reducesMotion), body)
}

extension MenuContrast {
    static func resolve(_ contrast: ColorSchemeContrast) -> MenuContrast {
        contrast == .increased ? .high : .standard
    }
}

extension View {
    func helpAndAccessibilityLabel(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }

    func accessibilityToggleState(_ isOn: Bool) -> some View {
        accessibilityValue(AccessibilityText.state(isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension View {
    func historyItemAccessibilityActions(_ item: HistoryItem) -> some View {
        accessibilityAction(named: Text("Copy URL".localized())) { HistoryActions.copyURL(item) }
            .accessibilityAction(named: Text("Open".localized())) { HistoryActions.open(item) }
            .accessibilityAction(named: Text("Delete".localized())) { HistoryActions.delete(item) }
    }
}

extension AfterCaptureStep {
    var accessibilityLabel: String {
        title.localized()
    }
}

extension EditorTool {
    var accessibilityLabel: String {
        title.localized()
    }
}
