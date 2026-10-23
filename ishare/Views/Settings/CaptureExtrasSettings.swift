import AppKit
import Defaults
import ishareCore
import SwiftUI

struct CaptureExtrasSettings: View {
    @Default(.hideMenuBarInCaptures) var hideMenuBar
    @Default(.blurredBundleIdentifiers) var blurredBundleIdentifiers
    @Default(.beautifyEnabled) var beautifyEnabled
    @Default(.beautifyWindowsOnly) var beautifyWindowsOnly
    @Default(.beautifyPadding) var padding
    @Default(.beautifyCornerRadius) var cornerRadius
    @Default(.beautifyShadow) var shadow
    @Default(.beautifyBackground) var background
    @Default(.beautifySolidColor) var solidColorHex
    @Default(.beautifyFrame) var frame
    @Default(.beautifyFrameAppearance) var frameAppearance
    @Default(.beautifyFrameFit) var frameFit
    @Default(.beautifyFrameTitle) var frameTitle
    @State private var isBlurredAppsSheetPresented = false

    var body: some View {
        Group {
            Section("Privacy".localized()) {
                Toggle("Hide the menu bar in screenshots".localized(), isOn: $hideMenuBar)
                LabeledContent("Blurred applications".localized()) {
                    HStack {
                        Text("\(blurredBundleIdentifiers.count)")
                            .foregroundStyle(.secondary)
                        Button("Edit…".localized()) { isBlurredAppsSheetPresented = true }
                    }
                }
            }
            Section("Background".localized()) {
                Toggle("Add a background to screenshots".localized(), isOn: $beautifyEnabled)
                if beautifyEnabled {
                    Toggle("Only for window captures".localized(), isOn: $beautifyWindowsOnly)
                    Picker("Style".localized(), selection: $background) {
                        ForEach(BeautifyBackground.allCases) { Text($0.title).tag($0) }
                    }
                    if background == .solid {
                        ColorPicker("Color".localized(), selection: solidColor, supportsOpacity: false)
                    }
                    LabeledContent("Padding".localized()) {
                        Slider(value: $padding, in: 0 ... 160, step: 4)
                        Text("\(Int(padding)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                    LabeledContent("Corner radius".localized()) {
                        Slider(value: $cornerRadius, in: 0 ... 40, step: 1)
                        Text("\(Int(cornerRadius)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                    Toggle("Drop shadow".localized(), isOn: $shadow)
                    Picker("Frame".localized(), selection: $frame) {
                        ForEach(DeviceFrame.allCases) { Text($0.title).tag($0) }
                    }
                    if frame != .none {
                        Picker("Frame appearance".localized(), selection: $frameAppearance) {
                            ForEach(DeviceFrameAppearance.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if frame == .browser {
                            TextField("Address bar text".localized(), text: $frameTitle, prompt: Text("Window title".localized()))
                        } else {
                            Picker("Screen fit".localized(), selection: $frameFit) {
                                ForEach(DeviceFrameFit.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    BeautifyPreview(style: previewStyle)
                }
            }
        }
        .sheet(isPresented: $isBlurredAppsSheetPresented) {
            BlurredAppsView()
                .frame(width: 380, height: 460)
        }
    }

    private var solidRGBA: CaptureColor {
        CaptureColor(hex: solidColorHex) ?? CaptureColor(red: 0.12, green: 0.12, blue: 0.18)
    }

    private var solidColor: Binding<Color> {
        Binding(
            get: { Color(cgColor: solidRGBA.cgColor) },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                solidColorHex = CaptureColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent).hex
            }
        )
    }

    private var previewStyle: BeautifyStyle {
        BeautifyStyle(
            background: background, solidColor: solidRGBA, padding: padding / 2,
            cornerRadius: cornerRadius / 2, shadow: shadow, scale: 1,
            frame: frame == .none ? nil : DeviceFrameStyle(kind: frame, appearance: frameAppearance, fit: frameFit, title: frameTitle.isEmpty ? "example.com" : frameTitle)
        )
    }
}

struct BeautifyPreview: View {
    let style: BeautifyStyle

    var body: some View {
        HStack {
            Spacer()
            if let image = Self.render(style) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 150)
                    .background(CheckerboardBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
        }
        .accessibilityHidden(true)
    }

    static let sample: CGImage? = {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 240, height: 150, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 150))
        context.setFillColor(CGColor(srgbRed: 0.88, green: 0.89, blue: 0.91, alpha: 1))
        context.fill(CGRect(x: 0, y: 128, width: 240, height: 22))
        for (index, color) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.79, 0.25)].enumerated() {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: 10 + CGFloat(index) * 16, y: 133, width: 11, height: 11))
        }
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.81, blue: 0.84, alpha: 1))
        for row in 0 ..< 5 {
            context.fill(CGRect(x: 16, y: 104 - row * 20, width: row.isMultiple(of: 2) ? 180 : 130, height: 8))
        }
        return context.makeImage()
    }()

    private static func render(_ style: BeautifyStyle) -> NSImage? {
        guard let sample, let output = Beautifier.apply(to: sample, style: style) else { return nil }
        return NSImage(cgImage: output, size: CGSize(width: output.width, height: output.height))
    }
}

struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            for row in 0 ..< Int(size.height / tile) + 1 {
                for column in 0 ..< Int(size.width / tile) + 1 where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.15)))
                }
            }
        }
    }
}
