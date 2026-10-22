import Defaults
import SwiftUI

struct SoundSettingsSection: View {
    @Default(.captureSound) private var captureSound
    @Default(.uploadCompleteSound) private var uploadCompleteSound
    private let choices = SoundPlayer.choices

    var body: some View {
        Section("Sounds".localized()) {
            soundPicker("Capture sound".localized(), selection: $captureSound, identifier: "settings.sounds.capture")
            soundPicker("Upload complete sound".localized(), selection: $uploadCompleteSound, identifier: "settings.sounds.upload")
        }
    }

    private func soundPicker(_ title: String, selection: Binding<SoundChoice>, identifier: String) -> some View {
        Picker(title, selection: Binding(
            get: { selection.wrappedValue },
            set: { choice in
                selection.wrappedValue = choice
                SoundPlayer.play(choice)
            }
        )) {
            Text(SoundChoice.none.title).tag(SoundChoice.none)
            Text(SoundChoice.beep.title).tag(SoundChoice.beep)
            Divider()
            ForEach(choices.filter { $0 != .none && $0 != .beep }, id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

extension HistoryLimit {
    var title: String {
        switch self {
        case .unlimited: "Unlimited".localized()
        default: String(format: "%d uploads".localized(), rawValue)
        }
    }
}

extension HistoryRetention {
    var title: String {
        switch self {
        case .never: "Never".localized()
        default: String(format: "%d days".localized(), rawValue)
        }
    }
}

struct HistorySettingsSection: View {
    @Default(.historyLimit) private var historyLimit
    @Default(.historyRetention) private var historyRetention
    @Default(.uploadHistory) private var uploadHistory

    var body: some View {
        Section("History".localized()) {
            Picker("Keep up to".localized(), selection: $historyLimit) {
                ForEach(HistoryLimit.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings.history.limit")
            Picker("Remove uploads older than".localized(), selection: $historyRetention) {
                ForEach(HistoryRetention.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings.history.retention")
            LabeledContent(String(format: "%d uploads in history".localized(), uploadHistory.count)) {
                Button("Clear History…".localized(), role: .destructive) {
                    _ = HistoryActions.confirmClearHistory()
                }
                .disabled(uploadHistory.isEmpty)
                .accessibilityIdentifier("settings.history.clear")
            }
        }
        .onChange(of: historyLimit) { applyHistoryLimits() }
        .onChange(of: historyRetention) { applyHistoryLimits() }
    }
}
