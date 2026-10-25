import AVFoundation
import Defaults
import ishareCore
import SwiftUI

struct VisibleBlurRegion: Identifiable {
    var region: BlurRegion
    var rect: CGRect

    var id: UUID { region.id }
}

struct TrimTimelineAnnotations: Equatable {
    var retiming: [RetimingSegment] = []
    var voiceClips: [ClosedRange<Double>] = []
    var blurSpans: [ClosedRange<Double>] = []
    var selectedSpan: ClosedRange<Double>?
    var keyframes: [Double] = []

    init() {}

    @MainActor init(model: TrimModel) {
        retiming = model.activePlan?.changedSegments ?? []
        voiceClips = model.voiceClips.map { $0.videoTime ... $0.end }
        blurSpans = model.blurRegions.map { $0.start ... $0.end }
        if let region = model.selectedRegion {
            selectedSpan = region.start ... region.end
            keyframes = region.track.keyframes.map(\.time)
        }
    }
}

struct TrimTimelineAnnotationsView: View {
    let annotations: TrimTimelineAnnotations
    let duration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(annotations.retiming.indices, id: \.self) { index in
                retimingBlock(annotations.retiming[index])
            }
            ForEach(annotations.blurSpans.indices, id: \.self) { index in
                strip(annotations.blurSpans[index], color: .teal.opacity(0.85), thickness: 4, y: 0)
            }
            if let selected = annotations.selectedSpan {
                strip(selected, color: .teal, thickness: 6, y: 0)
            }
            ForEach(annotations.keyframes.indices, id: \.self) { index in
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .offset(x: x(annotations.keyframes[index]) - 4, y: 6)
            }
            ForEach(annotations.voiceClips.indices, id: \.self) { index in
                strip(annotations.voiceClips[index], color: .purple, thickness: 5, y: height - 5)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func x(_ time: Double) -> CGFloat {
        duration > 0 ? CGFloat(min(max(time / duration, 0), 1)) * width : 0
    }

    private func retimingBlock(_ segment: RetimingSegment) -> some View {
        let isRemoved = segment.action == .remove
        return ZStack {
            Rectangle().fill((isRemoved ? Color.red : Color.blue).opacity(0.4))
            if case let .speed(factor) = segment.action, x(segment.end) - x(segment.start) > 24 {
                Text("\(Int(factor))×")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: max(1, x(segment.end) - x(segment.start)), height: height)
        .offset(x: x(segment.start))
    }

    private func strip(_ range: ClosedRange<Double>, color: Color, thickness: CGFloat, y: CGFloat) -> some View {
        Capsule()
            .fill(color)
            .frame(width: max(2, x(range.upperBound) - x(range.lowerBound)), height: thickness)
            .offset(x: x(range.lowerBound), y: y)
    }
}

struct TrimToolbar: View {
    @ObservedObject var model: TrimModel
    @State private var showsSilenceOptions = false
    @State private var showsVoiceOptions = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Cut silence".localized(), isOn: Binding(get: { model.cutsSilence }, set: { model.setCutsSilence($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Removes or speeds up stretches where it's quiet and the picture barely changes. Red parts are cut, blue parts play faster.".localized())
                .accessibilityIdentifier("trim.cutSilence")
            Button {
                showsSilenceOptions = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Silence options".localized())
            .popover(isPresented: $showsSilenceOptions, arrowEdge: .top) {
                Form {
                    SilenceDetectionRows(settings: $model.silenceSettings)
                }
                .formStyle(.grouped)
                .frame(width: 380)
            }
            if model.isAnalyzingSilence {
                ProgressView().controlSize(.small)
            }
            if let summary = model.silenceSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider().frame(height: 16)

            if model.voiceClips.isEmpty {
                Button {
                    model.startVoiceOver()
                } label: {
                    Label("Record Voice-Over".localized(), systemImage: "mic")
                }
                .disabled(model.voicePhase != .inactive)
                .accessibilityIdentifier("trim.voiceOver")
            } else {
                Menu {
                    Button("Record Again".localized()) { model.startVoiceOver() }
                    Button("Remove Voice-Over".localized(), role: .destructive) { model.removeVoiceOver() }
                } label: {
                    Label("Voice-Over".localized(), systemImage: "mic.fill")
                }
                .fixedSize()
                .disabled(model.voicePhase != .inactive)
            }
            Button {
                showsVoiceOptions = true
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help("Voice-over options".localized())
            .popover(isPresented: $showsVoiceOptions, arrowEdge: .top) {
                Form {
                    VoiceOverMixRows(mode: $model.voiceMode, duckAmount: $model.duckAmount)
                }
                .formStyle(.grouped)
                .frame(width: 380)
            }

            Divider().frame(height: 16)

            Toggle(isOn: $model.isEditingBlur) {
                Label("Blur Regions".localized(), systemImage: "eye.slash")
            }
            .toggleStyle(.button)
            .help("Draw boxes on the video to blur or pixelate them. They can follow moving content.".localized())
            .accessibilityIdentifier("trim.blur")

            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }
}

struct SilenceDetectionRows: View {
    @Binding var settings: SilenceDetectionSettings

    var body: some View {
        Picker("Silent parts".localized(), selection: $settings.speed) {
            ForEach(SilenceSpeed.allCases) { Text($0.title.localized()).tag($0) }
        }
        LabeledContent("Quieter than".localized()) {
            HStack {
                Slider(value: $settings.audioThreshold, in: SilenceDetectionSettings.audioThresholdRange, step: 1)
                Text("\(Int(settings.audioThreshold)) dB")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        LabeledContent("Picture changes less than".localized()) {
            HStack {
                Slider(value: $settings.motionThreshold, in: 0.001 ... 0.05)
                Text(String(format: "%.1f%%", settings.motionThreshold * 100))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        LabeledContent("Longer than".localized()) {
            HStack {
                Slider(value: $settings.minimumDuration, in: 0.5 ... 10, step: 0.5)
                Text(String(format: "%.1f s", settings.minimumDuration))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        LabeledContent("Keep around speech".localized()) {
            HStack {
                Slider(value: $settings.padding, in: SilenceDetectionSettings.paddingRange, step: 0.05)
                Text(String(format: "%.2f s", settings.padding))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

struct VoiceOverMixRows: View {
    @Binding var mode: VoiceOverMode
    @Binding var duckAmount: Double

    var body: some View {
        Picker("Original audio".localized(), selection: $mode) {
            ForEach(VoiceOverMode.allCases) { Text($0.title.localized()).tag($0) }
        }
        if mode == .duck {
            LabeledContent("Lower by".localized()) {
                HStack {
                    Slider(value: $duckAmount, in: DuckingSettings.reductionRange, step: 1)
                    Text("\(Int(duckAmount)) dB")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

struct VoiceOverCountdown: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 140, height: 140)
            .background(.black.opacity(0.55), in: Circle())
            .accessibilityLabel(Text(String(format: "Recording starts in %d".localized(), count)))
    }
}

struct VoiceOverBar: View {
    @ObservedObject var model: TrimModel
    @ObservedObject var recorder: VoiceOverRecorder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.voicePhase == .recording ? "record.circle.fill" : "mic.fill")
                .foregroundStyle(.red)
            Text(status)
                .font(.system(size: 12, weight: .semibold))
            AudioLevelMeter(level: recorder.level, width: 140, height: 6)
            Spacer()
            switch model.voicePhase {
            case .recording:
                Button("Pause".localized()) { model.pauseVoiceOver() }
            case .paused:
                Button("Resume".localized()) { model.resumeVoiceOver() }
            case .countdown, .inactive:
                EmptyView()
            }
            Button("Redo".localized()) { model.redoVoiceOver() }
            Button("Cancel".localized()) { model.cancelVoiceOver() }
            Button("Done".localized()) { model.finishVoiceOver() }
                .adaptiveGlassButtonStyle(prominent: true)
        }
        .controlSize(.small)
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("trim.voiceOver.bar")
    }

    private var status: String {
        switch model.voicePhase {
        case let .countdown(count): String(format: "Starting in %d…".localized(), count)
        case .recording: "Recording voice-over".localized()
        case .paused: "Voice-over paused".localized()
        case .inactive: ""
        }
    }
}

struct BlurRegionBar: View {
    @ObservedObject var model: TrimModel

    var body: some View {
        HStack(spacing: 10) {
            if let region = model.selectedRegion {
                Picker("Style".localized(), selection: Binding(get: { region.style }, set: { model.setRegionStyle(region.id, style: $0) })) {
                    ForEach(BlurRegionStyle.allCases) { Text($0.title.localized()).tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                Button("Set Start".localized()) { model.setRegionStart(region.id) }
                Button("Set End".localized()) { model.setRegionEnd(region.id) }
                Text("\(TrimView.format(region.start)) – \(TrimView.format(region.end))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Track Motion".localized()) { model.trackRegion(region.id) }
                    .help("Follows the content inside the box forward and backward from the current frame.".localized())
                Button("Remove Keyframe".localized()) { model.removeKeyframe(region.id) }
                    .disabled(region.track.keyframes.count < 2)
                Button(role: .destructive) {
                    model.removeRegion(region.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete region".localized())
            } else {
                Text("Drag on the video to cover an area. Move a box at another time to add a keyframe.".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.blurActivity != nil {
                Button("Stop".localized()) { model.cancelBlurActivity() }
            } else {
                Button("Find Sensitive Text".localized()) { model.detectSensitiveRegions() }
                    .help("Looks for email addresses, keys and other sensitive text in the video and covers it.".localized())
            }
        }
        .controlSize(.small)
        .disabled(model.isWorking)
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("trim.blur.bar")
    }
}

struct BlurEditingOverlay: View {
    @ObservedObject var model: TrimModel
    @State private var draft: CGRect?
    @State private var editing: VisibleBlurRegion?

    var body: some View {
        GeometryReader { geometry in
            let frame = videoFrame(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drawGesture(in: frame))
                ForEach(model.visibleRegions()) { visible in
                    let shown = editing?.id == visible.id ? editing ?? visible : visible
                    regionBox(shown, in: frame)
                }
                if let draft {
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(.white)
                        .frame(width: draft.width * frame.width, height: draft.height * frame.height)
                        .offset(x: frame.minX + draft.minX * frame.width, y: frame.minY + draft.minY * frame.height)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityIdentifier("trim.blur.canvas")
    }

    private func videoFrame(in size: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size)
        guard model.videoSize.width > 0, model.videoSize.height > 0 else { return bounds }
        return AVMakeRect(aspectRatio: model.videoSize, insideRect: bounds)
    }

    private func normalized(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: min(max((point.x - frame.minX) / max(1, frame.width), 0), 1), y: min(max((point.y - frame.minY) / max(1, frame.height), 0), 1))
    }

    private func drawGesture(in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = normalized(value.startLocation, in: frame)
                let end = normalized(value.location, in: frame)
                draft = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            }
            .onEnded { _ in
                if let draft, draft.width > 0.01, draft.height > 0.01 {
                    model.addBlurRegion(draft)
                }
                draft = nil
            }
    }

    private func regionBox(_ visible: VisibleBlurRegion, in frame: CGRect) -> some View {
        let rect = visible.rect
        let isSelected = model.selectedRegionID == visible.id
        let size = CGSize(width: rect.width * frame.width, height: rect.height * frame.height)
        return ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(.white.opacity(isSelected ? 0.12 : 0.04))
                .overlay(Rectangle().strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.8), lineWidth: isSelected ? 2 : 1))
                .contentShape(Rectangle())
                .onTapGesture { model.selectedRegionID = visible.id }
                .gesture(moveGesture(visible, in: frame))
            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .offset(x: 6, y: 6)
                    .gesture(resizeGesture(visible, in: frame))
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: frame.minX + rect.minX * frame.width, y: frame.minY + rect.minY * frame.height)
        .accessibilityLabel(Text(visible.region.style.title.localized()))
    }

    private func moveGesture(_ visible: VisibleBlurRegion, in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                model.selectedRegionID = visible.id
                var moved = visible
                moved.rect = RegionGeometry.clampedToUnit(
                    visible.rect.offsetBy(dx: value.translation.width / max(1, frame.width), dy: value.translation.height / max(1, frame.height)))
                editing = moved
            }
            .onEnded { _ in commitEditing() }
    }

    private func resizeGesture(_ visible: VisibleBlurRegion, in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                var resized = visible
                resized.rect = RegionGeometry.clampedToUnit(
                    CGRect(
                        x: visible.rect.minX, y: visible.rect.minY,
                        width: max(0.01, visible.rect.width + value.translation.width / max(1, frame.width)),
                        height: max(0.01, visible.rect.height + value.translation.height / max(1, frame.height))))
                editing = resized
            }
            .onEnded { _ in commitEditing() }
    }

    private func commitEditing() {
        if let editing { model.moveRegion(editing.id, to: editing.rect) }
        editing = nil
    }
}
