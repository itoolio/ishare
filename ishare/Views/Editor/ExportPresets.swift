import AppKit
import BezelNotification
import Defaults
import ImageIO
import ishareCore
import SwiftUI
import UniformTypeIdentifiers

extension ExportPreset: @retroactive Defaults.Serializable {}

extension ExportPreset.Format {
    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpg: .jpeg
        case .webp: UTType("org.webmproject.webp") ?? .image
        }
    }
}

@MainActor
enum ExportPresetRunner {
    static func data(for image: CGImage, preset: ExportPreset, pointScale: CGFloat) throws -> Data {
        let size = preset.outputSize(for: CGSize(width: image.width, height: image.height), pointScale: pointScale)
        let output = resized(image, to: size) ?? image
        switch preset.format {
        case .png:
            return try ImageEncoder.data(for: output, as: .PNG)
        case .webp:
            return try WebPEncoder.encode(output, quality: preset.quality)
        case .jpg:
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ImageEncoderError.destinationUnavailable
            }
            CGImageDestinationAddImage(destination, ImageEncoder.prepared(output, for: .JPG), [kCGImageDestinationLossyCompressionQuality: preset.quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ImageEncoderError.finalizeFailed }
            return data as Data
        }
    }

    static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard Int(size.width) != image.width || Int(size.height) != image.height,
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    static func run(_ preset: ExportPreset, document: EditorDocument) {
        document.commitPendingEdits()
        Defaults[.lastExportPresetID] = preset.id
        guard let rendered = document.render() else { return }
        do {
            let data = try data(for: rendered, preset: preset, pointScale: document.pointScale)
            switch preset.destination {
            case .clipboard:
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(preset.format.contentType.identifier))
                BezelNotification.show(messageText: String(format: "Copied for %@".localized(), preset.name), icon: ToastIcon)
            case .file:
                let panel = NSSavePanel()
                panel.allowedContentTypes = [preset.format.contentType]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = (document.fileURL?.deletingPathExtension().lastPathComponent ?? "ishare") + "." + preset.format.rawValue
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url, options: .atomic)
                BezelNotification.show(messageText: "Exported".localized(), icon: ToastIcon)
            }
        } catch {
            Log.app.error("Exporting with \(preset.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }
}

struct ExportPresetButton: View {
    let document: EditorDocument
    let beforeExport: (@escaping () -> Void) -> Void
    @Default(.exportPresets) private var presets
    @Default(.lastExportPresetID) private var lastID

    private var primary: ExportPreset? {
        presets.first { $0.id == lastID } ?? presets.first
    }

    var body: some View {
        if let primary {
            Menu {
                ForEach(presets) { preset in
                    Button(preset.name) { beforeExport { ExportPresetRunner.run(preset, document: document) } }
                }
            } label: {
                Label(primary.name, systemImage: primary.destination == .clipboard ? "doc.on.clipboard" : "square.and.arrow.down")
            } primaryAction: {
                beforeExport { ExportPresetRunner.run(primary, document: document) }
            }
            .fixedSize()
            .help("Export with a preset; click to use the last one".localized())
            .accessibilityIdentifier("editor.exportPreset")
        }
    }
}

struct ExportPresetSettings: View {
    @Default(.exportPresets) private var presets

    var body: some View {
        Section {
            ForEach($presets) { $preset in
                HStack {
                    TextField("Name".localized(), text: $preset.name)
                        .frame(maxWidth: 140)
                    Picker("Format".localized(), selection: $preset.format) {
                        ForEach(ExportPreset.Format.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("Longest side".localized(), value: $preset.maxDimension, format: .number)
                        .frame(width: 70)
                    Toggle("1×".localized(), isOn: $preset.downscalesRetina)
                        .help("Halve Retina images to their size in points".localized())
                    Picker("Destination".localized(), selection: $preset.destination) {
                        Text("Clipboard".localized()).tag(ExportPreset.Destination.clipboard)
                        Text("File".localized()).tag(ExportPreset.Destination.file)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button(role: .destructive) {
                        presets.removeAll { $0.id == preset.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove Preset".localized())
                }
            }
            HStack {
                Button("Add Preset".localized()) {
                    presets.append(ExportPreset(name: "Preset \(presets.count + 1)", format: .png))
                }
                Spacer()
                Button("Restore Defaults".localized()) { presets = ExportPreset.builtIn }
                    .disabled(presets == ExportPreset.builtIn)
            }
        } header: {
            Text("Editor Export Presets".localized())
        } footer: {
            Text("The editor’s preset button copies or saves the image with these settings. Leave the longest side empty to keep the full size.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
