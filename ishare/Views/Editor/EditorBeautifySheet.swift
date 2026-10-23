import AppKit
import Defaults
import ishareCore
import SwiftUI

struct EditorBeautifySheet: View {
    static let previewPixelSize: CGFloat = 560

    @ObservedObject var document: EditorDocument
    var onDismiss: () -> Void

    @State private var background = Defaults[.beautifyBackground]
    @State private var solidColor = CaptureColor(hex: Defaults[.beautifySolidColor]) ?? CaptureColor(red: 0.12, green: 0.12, blue: 0.18)
    @State private var padding = Defaults[.beautifyPadding]
    @State private var cornerRadius = Defaults[.beautifyCornerRadius]
    @State private var shadow = Defaults[.beautifyShadow]
    @State private var frame = Defaults[.beautifyFrame]
    @State private var frameAppearance = Defaults[.beautifyFrameAppearance]
    @State private var frameFit = Defaults[.beautifyFrameFit]
    @State private var frameTitle = Defaults[.beautifyFrameTitle]
    @State private var source: CGImage?
    @State private var previewSource: CGImage?

    private var scale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                preview
                    .frame(width: 360, height: 300)
                    .padding(16)
                Divider()
                Form { controls }
                    .formStyle(.grouped)
                    .frame(width: 320)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel".localized(), action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Apply".localized()) {
                    document.applyBeautify(style(previewFactor: 1))
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .adaptiveGlassButtonStyle(prominent: true)
                .accessibilityIdentifier("editor.beautify.apply")
            }
            .padding(12)
        }
        .onAppear {
            source = document.render()
            previewSource = source.map { ImageProcessing.resized($0, maxPixelSize: Self.previewPixelSize) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = previewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .background(CheckerboardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ProgressView()
        }
    }

    private var previewImage: CGImage? {
        guard let source, let previewSource else { return nil }
        let factor = CGFloat(previewSource.width) / CGFloat(max(1, source.width))
        return Beautifier.apply(to: previewSource, style: style(previewFactor: factor))
    }

    private func style(previewFactor: CGFloat) -> BeautifyStyle {
        let frameStyle = frame == .none ? nil : DeviceFrameStyle(kind: frame, appearance: frameAppearance, fit: frameFit, title: frameTitle)
        return BeautifyStyle(
            background: background, solidColor: solidColor, padding: padding, cornerRadius: cornerRadius,
            shadow: shadow, scale: scale * previewFactor, frame: frameStyle
        )
    }

    @ViewBuilder
    private var controls: some View {
        Section("Background".localized()) {
            Picker("Style".localized(), selection: $background) {
                ForEach(BeautifyBackground.allCases) { Text($0.title).tag($0) }
            }
            if background == .solid {
                ColorPicker(
                    "Color".localized(),
                    selection: Binding(
                        get: { Color(cgColor: solidColor.cgColor) },
                        set: { color in
                            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                            solidColor = CaptureColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
                        }
                    ), supportsOpacity: false)
            }
            LabeledContent("Padding".localized()) {
                Slider(value: $padding, in: 0 ... 160, step: 4)
            }
            LabeledContent("Corner radius".localized()) {
                Slider(value: $cornerRadius, in: 0 ... 40, step: 1)
            }
            Toggle("Drop shadow".localized(), isOn: $shadow)
        }
        Section("Frame".localized()) {
            Picker("Frame".localized(), selection: $frame) {
                ForEach(DeviceFrame.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("editor.beautify.frame")
            if frame != .none {
                Picker("Frame appearance".localized(), selection: $frameAppearance) {
                    ForEach(DeviceFrameAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if frame == .browser {
                    TextField("Address bar text".localized(), text: $frameTitle)
                } else {
                    Picker("Screen fit".localized(), selection: $frameFit) {
                        ForEach(DeviceFrameFit.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

struct EditorAdjustPanel: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        Form {
            Section("Straighten".localized()) {
                LabeledContent("Angle".localized()) {
                    HStack {
                        Slider(value: $document.straightenAngle, in: -StraightenGeometry.maximumAngle ... StraightenGeometry.maximumAngle, step: 0.1)
                            .frame(width: 150)
                            .accessibilityIdentifier("editor.straighten.angle")
                        Text(verbatim: String(format: "%.1f°", document.straightenAngle))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    Button("Reset".localized()) { document.straightenAngle = 0 }
                        .disabled(document.straightenAngle == 0)
                    Button("Straighten".localized()) { document.applyStraighten() }
                        .disabled(document.straightenAngle == 0)
                        .accessibilityIdentifier("editor.straighten.apply")
                }
            }
            Section("Adjustments".localized()) {
                adjustmentSlider("Brightness".localized(), value: \.brightness, range: ImageAdjustments.brightnessRange, identifier: "brightness")
                adjustmentSlider("Contrast".localized(), value: \.contrast, range: ImageAdjustments.contrastRange, identifier: "contrast")
                adjustmentSlider("Saturation".localized(), value: \.saturation, range: ImageAdjustments.saturationRange, identifier: "saturation")
                adjustmentSlider("Exposure".localized(), value: \.exposure, range: ImageAdjustments.exposureRange, identifier: "exposure")
                HStack {
                    Spacer()
                    Button("Reset Adjustments".localized()) { document.resetAdjustments() }
                        .disabled(document.adjustments.isIdentity)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func adjustmentSlider(_ title: String, value: WritableKeyPath<ImageAdjustments, Double>, range: ClosedRange<Double>, identifier: String) -> some View {
        LabeledContent(title) {
            Slider(
                value: Binding(
                    get: { document.adjustments[keyPath: value] },
                    set: { newValue in document.updateAdjustments { $0[keyPath: value] = newValue } }
                ), in: range
            ) { editing in
                if editing {
                    document.beginContinuousChange()
                } else {
                    document.endContinuousChange()
                }
            }
            .frame(width: 170)
            .accessibilityIdentifier("editor.adjust.\(identifier)")
        }
    }
}
