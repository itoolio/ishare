import Defaults
import Testing
@testable import ishare

@MainActor
@Suite(.serialized)
struct AfterCaptureStepTests {
    @Test func stepsFollowThePipelineOrder() {
        #expect(AfterCaptureStep.allCases == [.openEditor, .saveToDisk, .copyToClipboard, .openInFinder, .airdrop, .photos, .messages, .mail, .upload])
        #expect(AfterCaptureStep.allCases.map(\.group) == [.local, .local, .local, .local, .share, .share, .share, .share, .upload])
    }

    @Test func turningOffSaveToDiskAlsoTurnsOffFinder() {
        AfterCaptureStep.saveToDisk.isEnabled = true
        AfterCaptureStep.openInFinder.isEnabled = true
        #expect(AfterCaptureStep.openInFinder.isEnabled)
        AfterCaptureStep.saveToDisk.isEnabled = false
        #expect(!AfterCaptureStep.openInFinder.isEnabled)
        #expect(!Defaults[.openInFinder])
    }

    @Test func summaryListsEnabledStepsInOrder() {
        AfterCaptureStep.allCases.forEach { $0.isEnabled = false }
        #expect(AfterCaptureStep.summary == "Nothing happens after a capture".localized())
        AfterCaptureStep.upload.isEnabled = true
        AfterCaptureStep.openEditor.isEnabled = true
        #expect(AfterCaptureStep.enabledSteps == [.openEditor, .upload])
    }

    @Test func editorOnlyRunsForImagesAndForcedUploadsRunUploads() {
        AfterCaptureStep.openEditor.isEnabled = true
        AfterCaptureStep.upload.isEnabled = false
        #expect(AfterCaptureStep.openEditor.runs(for: .image, options: .standard))
        #expect(!AfterCaptureStep.openEditor.runs(for: .video, options: .standard))
        #expect(AfterCaptureStep.upload.runs(for: .image, options: CaptureOptions(forceUpload: true)))
        #expect(!AfterCaptureStep.upload.runs(for: .image, options: .standard))
    }
}
