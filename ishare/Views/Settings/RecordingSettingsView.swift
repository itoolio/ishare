import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct RecordingSettingsView: View {
    @Default(.recordMP4) var recordMP4
    @Default(.useHEVC) var useHEVC
    @Default(.useHDR) var useHDR
    @Default(.recordAudio) var recordAudio
    @Default(.recordingAudioSource) var audioSource
    @Default(.recordMic) var recordMic
    @Default(.recordPointer) var recordPointer
    @Default(.recordClicks) var recordClicks
    @Default(.recordingResolution) var resolution
    @Default(.recordingFrameRate) var frameRate
    @Default(.gifFrameRate) var gifFrameRate
    @Default(.compressBeforeUpload) var compressBeforeUpload
    @Default(.compressionThresholdMB) var compressionThresholdMB
    @Default(.compressionPreset) var compressionPreset
    @Default(.ignoredBundleIdentifiers) var ignoredBundleIdentifiers
    @State private var isExcludedAppSheetPresented = false

    var body: some View {
        Form {
            if ScreenshotMode.isCapturingScreenshots {
                RecordingExtrasSettings()
            }
            Section("Video".localized()) {
                Picker("Resolution".localized(), selection: $resolution) {
                    ForEach(RecordingResolution.allCases) { Text($0.title.localized()).tag($0) }
                }
                .accessibilityIdentifier("settings.recording.resolution")
                Picker("Frame rate".localized(), selection: $frameRate) {
                    ForEach(RecordingFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0) }
                }
                Toggle("Record .mp4 instead of .mov".localized(), isOn: $recordMP4)
                Toggle("Use HEVC".localized(), isOn: $useHEVC)
                Toggle("Use HDR".localized(), isOn: $useHDR)
            }
            Section("Content".localized()) {
                AudioSourceSettingsRows(audioSource: Binding(
                    get: { RecordingAudioSource.resolved(recordAudio: recordAudio, source: audioSource) },
                    set: { RecordingAudioSource.store($0) }
                ))
                Toggle("Record microphone".localized(), isOn: $recordMic)
                    .onChange(of: recordMic) { _, enabled in
                        guard enabled else { return }
                        Task { @MainActor in
                            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                                if !granted { recordMic = false }
                            }
                        }
                    }
                Toggle("Record pointer".localized(), isOn: $recordPointer)
                Toggle("Record clicks".localized(), isOn: $recordClicks)
                LabeledContent("Excluded applications".localized()) {
                    HStack {
                        Text("\(ignoredBundleIdentifiers.count)")
                            .foregroundStyle(.secondary)
                        Button("Edit…".localized()) { isExcludedAppSheetPresented = true }
                    }
                }
            }
            if !ScreenshotMode.isCapturingScreenshots {
                RecordingExtrasSettings()
            }
            Section("GIF".localized()) {
                Picker("GIF frame rate".localized(), selection: $gifFrameRate) {
                    ForEach(GIFFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0) }
                }
            }
            Section("Upload".localized()) {
                Toggle("Compress large recordings before upload".localized(), isOn: $compressBeforeUpload)
                if compressBeforeUpload {
                    Stepper(value: $compressionThresholdMB, in: 1 ... 4000, step: 5) {
                        LabeledContent("Larger than".localized(), value: "\(compressionThresholdMB) MB")
                    }
                    Picker("Compress to".localized(), selection: $compressionPreset) {
                        ForEach(CompressionPreset.allCases) { Text($0.title.localized()).tag($0) }
                    }
                }
            }
            Section("Files".localized()) {
                PrefixRow(key: .recordingFileName)
                FolderRow(title: "Video path:", kind: .recordings)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isExcludedAppSheetPresented) {
            ExcludedAppsView()
                .frame(width: 380, height: 460)
        }
    }
}
