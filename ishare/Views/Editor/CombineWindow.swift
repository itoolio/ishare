import AppKit
import BezelNotification
import Combine
import SwiftUI

@MainActor
final class CombineModel: ObservableObject {
    static let previewPixelSize: CGFloat = 640

    let images: [CGImage]
    private let previewImages: [CGImage]

    @Published var layout: CombineLayout = .horizontal { didSet { refresh() } }
    @Published var alignment: CombineAlignment = .center { didSet { refresh() } }
    @Published var columns = 2 { didSet { refresh() } }
    @Published var spacing: Double = 24 { didSet { refresh() } }
    @Published var padding: Double = 32 { didSet { refresh() } }
    @Published var cornerRadius: Double = 12 { didSet { refresh() } }
    @Published var shadow = false { didSet { refresh() } }
    @Published var background: BeautifyBackground = .transparent { didSet { refresh() } }
    @Published var solidColor = CaptureColor(red: 0.12, green: 0.12, blue: 0.18) { didSet { refresh() } }
    @Published private(set) var preview: CGImage?

    init(images: [CGImage]) {
        self.images = images
        previewImages = images.map { ImageProcessing.resized($0, maxPixelSize: Self.previewPixelSize) }
        columns = ImageCombiner.gridColumns(for: images.count, preferred: nil)
        refresh()
    }

    var previewScale: CGFloat {
        guard let first = images.first, let preview = previewImages.first, first.width > 0 else { return 1 }
        return CGFloat(preview.width) / CGFloat(first.width)
    }

    func style(scale: CGFloat) -> CombineStyle {
        let fill = BeautifyStyle(background: background, solidColor: solidColor, padding: 0, cornerRadius: 0, shadow: false, scale: 1).fill
        return CombineStyle(
            layout: layout,
            alignment: alignment,
            spacing: spacing * scale,
            padding: padding * scale,
            cornerRadius: cornerRadius * scale,
            shadowRadius: shadow ? max(4, min(28, padding * 0.5)) * scale : 0,
            fill: fill,
            columns: layout == .grid ? columns : nil
        )
    }

    func render() -> CGImage? {
        ImageCombiner.combine(images, style: style(scale: 1))
    }

    private func refresh() {
        preview = ImageCombiner.combine(previewImages, style: style(scale: previewScale))
    }
}

@MainActor
final class CombineWindowController: NSObject, NSWindowDelegate {
    private static var open: [CombineWindowController] = []

    private let model: CombineModel
    private var window: NSWindow?

    private init(model: CombineModel) {
        self.model = model
    }

    static func present(urls: [URL], leading: [CGImage] = []) {
        let loaded = urls.compactMap(ImageEncoder.loadImage(at:))
        let images = leading + loaded
        guard images.count >= 2 else {
            BezelNotification.show(messageText: "Choose at least two images to combine".localized(), icon: ToastIcon)
            return
        }
        let controller = CombineWindowController(model: CombineModel(images: images))
        open.append(controller)
        controller.show()
    }

    private func show() {
        let view = CombineView(
            model: model,
            onCancel: { [weak self] in self?.window?.close() },
            onCombine: { [weak self] in self?.finish() }
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.title = "Combine Images".localized()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = CGSize(width: 760, height: 480)
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        guard let combined = model.render() else {
            BezelNotification.show(messageText: "Couldn't combine the images".localized(), icon: ToastIcon)
            return
        }
        let preservesTransparency = model.background == .transparent
        window?.close()
        Task { @MainActor in
            await NewCaptureDocument.openInEditor(combined, suffix: "combined", preservesTransparency: preservesTransparency)
        }
    }

    func windowWillClose(_: Notification) {
        window?.delegate = nil
        window = nil
        Self.open.removeAll { $0 === self }
    }
}

struct CombineView: View {
    @ObservedObject var model: CombineModel
    var onCancel: () -> Void
    var onCombine: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
                .background(Color.black.opacity(0.12))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Form { controls }
                    .formStyle(.grouped)
                HStack {
                    Spacer()
                    Button("Cancel".localized(), action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Open in Editor".localized(), action: onCombine)
                        .keyboardShortcut(.defaultAction)
                        .adaptiveGlassButtonStyle(prominent: true)
                        .accessibilityIdentifier("combine.open")
                }
                .padding(14)
            }
            .frame(width: 320)
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = model.preview {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .background(CheckerboardBackground())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                .accessibilityIdentifier("combine.preview")
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        Section {
            Picker("Layout".localized(), selection: $model.layout) {
                ForEach(CombineLayout.allCases) { layout in
                    Label(layout.title, systemImage: layout.symbol).tag(layout)
                }
            }
            .accessibilityIdentifier("combine.layout")
            if model.layout == .grid {
                Stepper(value: $model.columns, in: 1 ... max(1, model.images.count)) {
                    LabeledContent("Columns".localized(), value: "\(model.columns)")
                }
            }
            Picker("Alignment".localized(), selection: $model.alignment) {
                ForEach(CombineAlignment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent("Spacing".localized()) {
                Slider(value: $model.spacing, in: 0 ... 160, step: 4)
            }
            LabeledContent("Padding".localized()) {
                Slider(value: $model.padding, in: 0 ... 200, step: 4)
            }
            LabeledContent("Corner radius".localized()) {
                Slider(value: $model.cornerRadius, in: 0 ... 60, step: 1)
            }
            Toggle("Drop shadow".localized(), isOn: $model.shadow)
        }
        Section("Background".localized()) {
            Picker("Style".localized(), selection: $model.background) {
                ForEach(BeautifyBackground.allCases) { Text($0.title).tag($0) }
            }
            if model.background == .solid {
                ColorPicker("Color".localized(), selection: Binding(
                    get: { Color(cgColor: model.solidColor.cgColor) },
                    set: { color in
                        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                        model.solidColor = CaptureColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
                    }
                ), supportsOpacity: false)
            }
        }
    }
}
