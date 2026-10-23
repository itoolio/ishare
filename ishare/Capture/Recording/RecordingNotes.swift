import AppKit
import Defaults
import SwiftUI

enum RecordingNotesLayout {
    static let defaultSize = CGSize(width: 360, height: 260)
    static let minimumSize = CGSize(width: 240, height: 160)
    static let inset: CGFloat = 24
    static let fontSizeRange: ClosedRange<Double> = 10 ... 72
    static let scrollSpeedRange: ClosedRange<Double> = 0 ... 120
    static let opacityRange: ClosedRange<Double> = 0.3 ... 1

    static func defaultFrame(in visibleFrame: CGRect) -> CGRect {
        let width = min(defaultSize.width, max(minimumSize.width, visibleFrame.width - inset * 2))
        let height = min(defaultSize.height, max(minimumSize.height, visibleFrame.height - inset * 2))
        return CGRect(x: visibleFrame.maxX - inset - width, y: visibleFrame.maxY - inset - height, width: width, height: height)
    }

    static func steppedFontSize(_ size: Double, by step: Double) -> Double {
        min(max(size + step, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }
}

enum TeleprompterScroll {
    static func offset(elapsed: Double, speed: Double, contentHeight: Double, viewportHeight: Double) -> Double {
        guard elapsed > 0, speed > 0 else { return 0 }
        return min(elapsed * speed, max(0, contentHeight - viewportHeight))
    }

    static func hasReachedEnd(elapsed: Double, speed: Double, contentHeight: Double, viewportHeight: Double) -> Bool {
        let limit = max(0, contentHeight - viewportHeight)
        return speed > 0 && elapsed * speed >= limit
    }
}

enum RecordingCaptureExclusion {
    static func capturedOverlayIDs(overlays: [CGWindowID], privateWindows: [CGWindowID?]) -> Set<CGWindowID> {
        Set(overlays).subtracting(privateWindows.compactMap(\.self))
    }
}

private final class RecordingNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RecordingNotesController: NSObject, NSWindowDelegate {
    static let shared = RecordingNotesController()
    private static let autosaveName = "ishare.recordingNotes"

    private var panel: NSPanel?
    private var opacityTask: Task<Void, Never>?

    var isVisible: Bool { panel?.isVisible == true }

    var windowID: CGWindowID? {
        guard let panel, panel.windowNumber > 0 else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    func toggle() {
        if isVisible {
            Defaults[.showRecordingNotes] = false
            hide()
        } else {
            Defaults[.showRecordingNotes] = true
            show()
        }
    }

    func recordingDidStart() {
        guard Defaults[.showRecordingNotes] else { return }
        show()
    }

    func recordingDidStop() {
        hide()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.alphaValue = Defaults[.recordingNotesOpacity]
        panel.orderFrontRegardless()
        observeOpacity()
    }

    func hide() {
        opacityTask?.cancel()
        opacityTask = nil
        panel?.orderOut(nil)
    }

    func windowWillClose(_: Notification) {
        Defaults[.showRecordingNotes] = false
        opacityTask?.cancel()
        opacityTask = nil
    }

    private func observeOpacity() {
        opacityTask?.cancel()
        opacityTask = Task { @MainActor [weak self] in
            for await opacity in Defaults.updates(.recordingNotesOpacity, initial: false) {
                self?.panel?.alphaValue = opacity
            }
        }
    }

    private func makePanel() -> NSPanel {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let panel = RecordingNotesPanel(
            contentRect: RecordingNotesLayout.defaultFrame(in: visible),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Notes".localized()
        panel.sharingType = .none
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = RecordingNotesLayout.minimumSize
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: RecordingNotesView())
        panel.setFrameAutosaveName(Self.autosaveName)
        panel.setAccessibilityIdentifier("recording.notes")
        return panel
    }
}

private struct TeleprompterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RecordingNotesView: View {
    private enum Mode: Hashable {
        case edit
        case prompt
    }

    @Default(.recordingNotesText) private var text
    @Default(.recordingNotesFontSize) private var fontSize
    @Default(.recordingNotesScrollSpeed) private var scrollSpeed
    @Default(.recordingNotesOpacity) private var opacity
    @State private var mode = Mode.edit
    @State private var playStart: Date?
    @State private var accumulated: Double = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            switch mode {
            case .edit:
                TextEditor(text: $text)
                    .font(.system(size: fontSize))
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("recording.notes.text")
            case .prompt:
                teleprompter
            }
            controls
        }
        .padding(10)
        .frame(minWidth: RecordingNotesLayout.minimumSize.width, minHeight: RecordingNotesLayout.minimumSize.height)
        .onChange(of: mode) { _, _ in resetScroll() }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Picker("Mode".localized(), selection: $mode) {
                Text("Edit".localized()).tag(Mode.edit)
                Text("Teleprompter".localized()).tag(Mode.prompt)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
            if mode == .prompt {
                Button(action: togglePlayback) {
                    Image(systemName: playStart == nil ? "play.fill" : "pause.fill")
                }
                .disabled(scrollSpeed <= 0)
                .help("Start or pause scrolling".localized())
                Button(action: resetScroll) {
                    Image(systemName: "backward.end.fill")
                }
                .help("Back to the top".localized())
            }
            Button { fontSize = RecordingNotesLayout.steppedFontSize(fontSize, by: -2) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .help("Smaller text".localized())
            Button { fontSize = RecordingNotesLayout.steppedFontSize(fontSize, by: 2) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .help("Larger text".localized())
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.to.line")
                .help("Teleprompter scroll speed".localized())
            Slider(value: $scrollSpeed, in: RecordingNotesLayout.scrollSpeedRange)
                .accessibilityLabel(Text("Teleprompter scroll speed".localized()))
            Image(systemName: "circle.lefthalf.filled")
                .help("Opacity".localized())
            Slider(value: $opacity, in: RecordingNotesLayout.opacityRange)
                .accessibilityLabel(Text("Opacity".localized()))
        }
        .controlSize(.mini)
        .foregroundStyle(.secondary)
    }

    private var teleprompter: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: playStart == nil)) { context in
                let elapsed = accumulated + (playStart.map { context.date.timeIntervalSince($0) } ?? 0)
                Text(text.isEmpty ? "Write your notes in Edit mode.".localized() : text)
                    .font(.system(size: fontSize, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { Color.clear.preference(key: TeleprompterHeightKey.self, value: $0.size.height) })
                    .offset(y: -TeleprompterScroll.offset(elapsed: elapsed, speed: scrollSpeed, contentHeight: contentHeight, viewportHeight: proxy.size.height))
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .onPreferenceChange(TeleprompterHeightKey.self) { contentHeight = $0 }
        .accessibilityIdentifier("recording.notes.teleprompter")
    }

    private func togglePlayback() {
        if let playStart {
            accumulated += Date().timeIntervalSince(playStart)
            self.playStart = nil
        } else {
            playStart = Date()
        }
    }

    private func resetScroll() {
        playStart = nil
        accumulated = 0
    }
}
