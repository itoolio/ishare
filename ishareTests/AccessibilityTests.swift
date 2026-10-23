import Foundation
import SwiftUI
import Testing
@testable import ishare

@MainActor
struct AccessibilityLabelTests {
    @Test(arguments: AfterCaptureStep.allCases)
    func everyAfterCaptureStepHasALabel(step: AfterCaptureStep) {
        #expect(!step.accessibilityLabel.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test func afterCaptureStepLabelsAreDistinct() {
        let labels = AfterCaptureStep.allCases.map(\.accessibilityLabel)
        #expect(Set(labels).count == labels.count)
    }

    @Test(arguments: EditorTool.allCases)
    func everyEditorToolHasALabel(tool: EditorTool) {
        #expect(!tool.accessibilityLabel.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test func editorToolLabelsAreDistinct() {
        let labels = EditorTool.allCases.map(\.accessibilityLabel)
        #expect(Set(labels).count == labels.count)
    }

    @Test func toggleStatesReadAsOnAndOff() {
        #expect(AccessibilityText.state(true) == "On".localized())
        #expect(AccessibilityText.state(false) == "Off".localized())
        #expect(AccessibilityText.state(true) != AccessibilityText.state(false))
    }
}

struct MotionPreferenceTests {
    @Test func reducedMotionDropsAnimations() {
        #expect(MotionPreference.animation(.snappy, reducesMotion: true) == nil)
        #expect(MotionPreference.animation(.snappy, reducesMotion: false) != nil)
    }

    @Test func reducedMotionShortensDurations() {
        #expect(MotionPreference.duration(0.2, reducesMotion: true) == 0)
        #expect(MotionPreference.duration(0.2, reducesMotion: false) == 0.2)
    }
}

struct ContrastResolutionTests {
    @Test func increasedSystemContrastUsesTheHighContrastStyle() {
        #expect(MenuContrast.resolve(ColorSchemeContrast.increased) == .high)
        #expect(MenuContrast.resolve(ColorSchemeContrast.standard) == .standard)
        #expect(MenuContrast.high.borderOpacity > MenuContrast.standard.borderOpacity)
    }
}
