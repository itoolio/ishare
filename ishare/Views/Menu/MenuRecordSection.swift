import SwiftUI

struct MenuRecordFormatPicker: View {
    let isRecording: Bool
    @Binding var recordsGIF: Bool

    var body: some View {
        if !isRecording {
            Picker("", selection: $recordsGIF) {
                Text("Video".localized()).tag(false)
                Text("GIF").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .fixedSize()
            .accessibilityIdentifier("menu.record.format")
        }
    }
}

struct MenuRecordSection: View {
    let isRecording: Bool
    let startDate: Date?
    let recordsGIF: Bool
    @EnvironmentObject private var app: AppModel
    @Environment(\.menuMetrics) private var metrics

    var body: some View {
        if isRecording {
            stopButton
        } else {
            HStack(spacing: 8) {
                WideActionButton(
                    symbol: recordsGIF ? "photo.stack" : "record.circle",
                    title: "Screen",
                    help: "Pick a screen or window to record",
                    shortcut: recordsGIF ? .recordGif : .recordScreen,
                    identifier: recordsGIF ? "menu.record.gif" : "menu.record.screen"
                ) {
                    app.menuActions.toggleRecording(gif: recordsGIF)
                }
                .favoriteContextMenu(MenuFavoriteCommandID.record(0, gif: recordsGIF))
                .menuFocusRing(.record(0))
                WideActionButton(
                    symbol: "rectangle.dashed.badge.record",
                    title: "Region",
                    shortcut: recordsGIF ? .recordRegionGif : .recordRegion,
                    identifier: recordsGIF ? "menu.record.regiongif" : "menu.record.region"
                ) {
                    app.menuActions.toggleRecording(gif: recordsGIF, region: true)
                }
                .favoriteContextMenu(MenuFavoriteCommandID.record(1, gif: recordsGIF))
                .menuFocusRing(.record(1))
            }
            MenuRecordPresetsRow(recordsGIF: recordsGIF)
            MenuExternalDevicesRows()
        }
    }

    private var stopButton: some View {
        HStack(spacing: 6) {
            Button {
                app.menuActions.stopRecording()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Stop Recording".localized())
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let startDate {
                        TimelineView(.periodic(from: startDate, by: 1)) { _ in
                            HStack(spacing: 6) {
                                Text(RecordingStatusText.clock(app.recorder.recordedTime))
                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                    .accessibilityIdentifier("menu.record.elapsed")
                                if let remaining = app.recorder.remainingTime {
                                    Text(RecordingStatusText.remaining(remaining))
                                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                                        .opacity(0.8)
                                        .help("Time left before the recording stops automatically".localized())
                                        .accessibilityIdentifier("menu.record.remaining")
                                }
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: metrics.wideHeight)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(app.recorder.isPaused ? Color.orange : Color.red))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuFocusRing(.stopRecording)
            .accessibilityIdentifier("menu.record.stop")
            if startDate != nil {
                pauseButton
            }
        }
    }

    private var pauseButton: some View {
        Button {
            app.menuActions.togglePauseRecording()
        } label: {
            Image(systemName: app.recorder.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: metrics.wideHeight, height: metrics.wideHeight)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.6)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.recorder.isPaused ? "Resume Recording".localized() : "Pause Recording".localized())
        .accessibilityLabel(Text(app.recorder.isPaused ? "Resume Recording".localized() : "Pause Recording".localized()))
        .accessibilityIdentifier("menu.record.pause")
    }
}
