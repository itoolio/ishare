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
                    MenuActions.toggleRecording(gif: recordsGIF)
                }
                .favoriteContextMenu(MenuFavoriteCommandID.record(0, gif: recordsGIF))
                .menuFocusRing(.record(0))
                WideActionButton(
                    symbol: "rectangle.dashed.badge.record",
                    title: "Region",
                    shortcut: recordsGIF ? .recordRegionGif : .recordRegion,
                    identifier: recordsGIF ? "menu.record.regiongif" : "menu.record.region"
                ) {
                    MenuActions.toggleRecording(gif: recordsGIF, region: true)
                }
                .favoriteContextMenu(MenuFavoriteCommandID.record(1, gif: recordsGIF))
                .menuFocusRing(.record(1))
            }
        }
    }

    private var stopButton: some View {
        Button {
            MenuActions.stopRecording()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Stop Recording".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let startDate {
                    TimelineView(.periodic(from: startDate, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(startDate)).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: metrics.wideHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuFocusRing(.stopRecording)
        .accessibilityIdentifier("menu.record.stop")
    }
}
