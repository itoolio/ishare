import Defaults
import ishareCore
import SwiftUI

struct RecordingPostProcessingSettings: View {
    @Default(.cutSilenceEnabled) private var cutSilenceEnabled
    @Default(.cutSilenceSpeed) private var speed
    @Default(.cutSilenceAudioThreshold) private var audioThreshold
    @Default(.cutSilenceMotionThreshold) private var motionThreshold
    @Default(.cutSilenceMinimumDuration) private var minimumDuration
    @Default(.cutSilencePadding) private var padding
    @Default(.recordingConvertTo) private var convertTo
    @Default(.recordingUploadFormat) private var uploadFormat
    @Default(.voiceOverMode) private var voiceOverMode
    @Default(.voiceOverDuckAmount) private var duckAmount
    @Default(.blurRegionStyle) private var blurStyle
    @Default(.blurDetectionInterval) private var detectionInterval

    var body: some View {
        Group {
            Section {
                Toggle("Cut silence".localized(), isOn: $cutSilenceEnabled)
                    .accessibilityIdentifier("settings.recording.cutSilence")
                if cutSilenceEnabled {
                    SilenceDetectionRows(settings: silenceSettings)
                }
            } header: {
                Text("Cut Silence".localized())
            } footer: {
                Text(
                    "Finds stretches where the audio stays quiet and the picture barely changes, then removes them or plays them faster. With “Trim recordings before saving” on, the trim window shows the cuts on the timeline before anything is changed."
                        .localized()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("Convert to".localized(), selection: $convertTo) {
                    ForEach(RecordingConversion.allCases) { conversion in
                        Text(title(for: conversion, emptyTitle: "Keep the video".localized()))
                            .tag(conversion)
                            .selectionDisabled(!conversion.isAvailable)
                    }
                }
                .accessibilityIdentifier("settings.recording.convertTo")
                Picker("Upload recordings as".localized(), selection: $uploadFormat) {
                    ForEach(RecordingConversion.allCases) { conversion in
                        Text(title(for: conversion, emptyTitle: "Video".localized()))
                            .tag(conversion)
                            .selectionDisabled(!conversion.isAvailable)
                    }
                }
                .accessibilityIdentifier("settings.recording.uploadFormat")
            } header: {
                Text("Animated Images".localized())
            } footer: {
                Text(animatedFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                VoiceOverMixRows(mode: $voiceOverMode, duckAmount: $duckAmount)
            } header: {
                Text("Voice-Over".localized())
            } footer: {
                Text("Record a voice-over from the trim window while the video plays. These options decide what happens to the recording's own sound.".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Blur Regions".localized()) {
                Picker("Default style".localized(), selection: $blurStyle) {
                    ForEach(BlurRegionStyle.allCases) { Text($0.title.localized()).tag($0) }
                }
                Picker("Check for sensitive text every".localized(), selection: $detectionInterval) {
                    ForEach([0.5, 1, 2, 5], id: \.self) { interval in
                        Text(String(format: "%.1f s", interval)).tag(interval)
                    }
                }
            }
        }
    }

    private var silenceSettings: Binding<SilenceDetectionSettings> {
        Binding(
            get: {
                SilenceDetectionSettings(
                    audioThreshold: audioThreshold, motionThreshold: motionThreshold, minimumDuration: minimumDuration, padding: padding, speed: speed)
            },
            set: { settings in
                audioThreshold = settings.audioThreshold
                motionThreshold = settings.motionThreshold
                minimumDuration = settings.minimumDuration
                padding = settings.padding
                speed = settings.speed
            }
        )
    }

    private var animatedFooter: String {
        let base = "Converted recordings keep the GIF frame rate and size. Uploads are converted on the way out, so the saved video stays as it is.".localized()
        guard !AnimatedImageFormat.webp.isAvailable else { return base }
        return base + " " + AnimatedImageFormat.unavailableMessage
    }

    private func title(for conversion: RecordingConversion, emptyTitle: String) -> String {
        guard let format = conversion.animatedFormat else { return emptyTitle }
        return conversion.isAvailable ? format.title : String(format: "%@ (not available)".localized(), format.title)
    }
}

extension RecordingPostProcessingSettings: SettingsSearchable {
    static let searchEntries: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            "Cut Silence", pane: .recording,
            keywords: [
                "Cut silence", "Silence", "Silent parts", "Speed up", "Quieter than", "Picture changes less than", "Longer than", "Keep around speech",
                "Pauses", "Dead air",
            ]),
        SettingsSearchEntry(
            "Animated Images", pane: .recording,
            keywords: ["Convert to", "Upload recordings as", "APNG", "WebP", "GIF", "Animated PNG", "Animation"]),
        SettingsSearchEntry(
            "Voice-Over", pane: .recording,
            keywords: ["Voice-over", "Narration", "Original audio", "Lower by", "Duck", "Ducking", "Replace audio", "Microphone"]),
        SettingsSearchEntry(
            "Blur Regions", pane: .recording,
            keywords: ["Blur", "Pixelate", "Redact", "Default style", "Check for sensitive text every", "Tracking", "Sensitive text"]),
    ]
}
