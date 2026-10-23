import Defaults
import SwiftUI

struct CaptureToolsSettings: View {
    @Default(.captureDelay) var captureDelay
    @Default(.copyLinksFromCodes) var copyLinksFromCodes
    @Default(.redactBeforeUpload) var redactBeforeUpload
    @Default(.redactSavedFile) var redactSavedFile
    @Default(.redactionCategories) var redactionCategories
    @Default(.intervalCaptureInterval) var interval
    @Default(.intervalCaptureStopMode) var stopMode
    @Default(.intervalCaptureFrameCount) var frameCount
    @Default(.intervalCaptureDuration) var duration
    @Default(.intervalCaptureMakesGIF) var makesGIF
    @Default(.captureProfiles) var profiles
    @Default(.translationTargetLanguage) var translationTargetLanguage
    @Default(.generateAltText) var generateAltText
    @State private var translationLanguages: [TranslationLanguageOption] = []
    @State private var isProfilesSheetPresented = false

    var body: some View {
        Group {
            Section {
                Picker("Capture delay".localized(), selection: $captureDelay) {
                    ForEach(CaptureDelay.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Copy links from QR codes".localized(), isOn: $copyLinksFromCodes)
            } header: {
                Text("Timer & Codes".localized())
            } footer: {
                Text("The delay applies to screen and window captures. A countdown appears next to the pointer; press Esc to cancel it, even after you click into another app.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Redact sensitive text before uploading".localized(), isOn: $redactBeforeUpload)
                if redactBeforeUpload {
                    ForEach(RedactionCategory.allCases) { category in
                        Toggle(category.title.localized(), isOn: binding(for: category))
                    }
                    Toggle("Also redact the saved file".localized(), isOn: $redactSavedFile)
                }
            } header: {
                Text("Redaction".localized())
            } footer: {
                Text("ishare reads the text in a screenshot on this Mac and pixelates matching text in the copy it uploads.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Interval Capture".localized()) {
                Picker("Interval".localized(), selection: $interval) {
                    ForEach(CaptureInterval.allCases) { Text($0.title).tag($0) }
                }
                Picker("Stop after".localized(), selection: $stopMode) {
                    ForEach(IntervalStopMode.allCases) { Text($0.title.localized()).tag($0) }
                }
                if stopMode == .frameCount {
                    Stepper(value: $frameCount, in: IntervalPlan.frameCountRange) {
                        LabeledContent("Frames".localized(), value: "\(frameCount)")
                    }
                } else {
                    Picker("Duration".localized(), selection: $duration) {
                        ForEach(IntervalPlan.durationChoices, id: \.self) { Text(IntervalPlan.durationTitle($0)).tag($0) }
                    }
                }
                Toggle("Also make a GIF".localized(), isOn: $makesGIF)
            }
            Section {
                Picker("Translate to".localized(), selection: $translationTargetLanguage) {
                    Text("System Language".localized()).tag("")
                    ForEach(translationLanguages) { Text($0.name).tag($0.id) }
                }
                if OnDeviceModel.isAvailable {
                    Toggle("Generate alt text for uploads".localized(), isOn: $generateAltText)
                }
            } header: {
                Text("Translate & Describe".localized())
            } footer: {
                Text(intelligenceFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Profiles".localized()) {
                    HStack {
                        Text("\(profiles.count)")
                            .foregroundStyle(.secondary)
                        Button("Edit…".localized()) { isProfilesSheetPresented = true }
                    }
                }
            } header: {
                Text("App Profiles".localized())
            } footer: {
                Text("Profiles change the background, privacy blur, window shadow and file prefix when you capture a specific app.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            translationLanguages = TranslationLanguages.options(await TranslationLanguages.supportedLanguages(), including: selectedTranslationLanguage)
        }
        .sheet(isPresented: $isProfilesSheetPresented) {
            CaptureProfilesView()
                .frame(width: 520, height: 460)
        }
    }

    private var selectedTranslationLanguage: [Locale.Language] {
        translationTargetLanguage.isEmpty ? [] : [Locale.Language(identifier: translationTargetLanguage)]
    }

    private var intelligenceFooter: String {
        let translation = "Capture and Translate recognizes the text in an area and translates it on this Mac with Apple's Translation languages.".localized()
        guard OnDeviceModel.isAvailable else { return translation }
        let altText = "Alt text is written on this Mac by Apple Intelligence from the text and objects ishare recognizes, and saved with the upload in your history.".localized()
        return translation + " " + altText
    }

    private func binding(for category: RedactionCategory) -> Binding<Bool> {
        Binding(
            get: { redactionCategories.contains(category) },
            set: { isOn in
                if isOn {
                    redactionCategories.insert(category)
                } else {
                    redactionCategories.remove(category)
                }
            }
        )
    }
}
