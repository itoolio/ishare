import Defaults
import ishareCore
import SwiftUI

struct ImageUploadSettings: View {
    @Default(.optimizeImagesBeforeUpload) var optimizeImagesBeforeUpload
    @Default(.imageOptimizationFormat) var imageOptimizationFormat
    @Default(.imageConversionQuality) var imageConversionQuality
    @Default(.stripImageMetadata) var stripImageMetadata
    @Default(.stripImportedImageMetadata) var stripImportedImageMetadata

    var body: some View {
        Section {
            Toggle("Optimize images before upload".localized(), isOn: $optimizeImagesBeforeUpload)
                .settingsEntry(Self.optimization)
            if optimizeImagesBeforeUpload {
                Picker("Format".localized(), selection: $imageOptimizationFormat) {
                    ForEach(ImageOptimizationFormat.allCases) { format in
                        Text(format.titleKey.localized()).tag(format)
                    }
                }
                if imageOptimizationFormat != .lossless {
                    LabeledContent("Quality".localized()) {
                        Slider(value: $imageConversionQuality, in: 0.5 ... 1, step: 0.05)
                            .frame(width: 180)
                        Text(imageConversionQuality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    if let note = fallbackNote {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(
                    "PNGs are recompressed losslessly and their ancillary chunks dropped. The smaller file is uploaded only when it saves space; you can turn this off or keep the original format for single uploaders in their settings."
                        .localized()
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Toggle("Remove location and camera details from imported photos".localized(), isOn: $stripImportedImageMetadata)
                .settingsEntry(Self.metadata)
            Toggle("Remove location and camera details from every upload".localized(), isOn: $stripImageMetadata)
            Text(
                "Removes GPS location, camera make and model, maker notes, IPTC and XMP data before uploading. Orientation and color profile are kept. Imported photos are images from Continuity Camera, dropped files, the Services menu and the watch folder."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Images".localized())
        }
    }

    private var fallbackNote: String? {
        switch imageOptimizationFormat {
        case .avif where !ImageEncoders.canEncode(ImageEncoders.avif):
            "This Mac can't encode AVIF, so ishare uses HEIC instead.".localized()
        case .webp where !ImageEncoders.canEncode(ImageEncoders.webp):
            "This Mac can't encode WebP, so images keep their format and are only recompressed losslessly.".localized()
        default:
            nil
        }
    }
}

extension ImageUploadSettings {
    static let optimization = SettingsSearchEntry(
        "Optimize images before upload", pane: .uploaders,
        keywords: ["Optimize", "Compress", "PNG", "AVIF", "WebP", "HEIC", "Smaller", "Saved"], anchor: "uploaders.imageOptimization"
    )
    static let metadata = SettingsSearchEntry(
        "Remove location and camera details from imported photos", pane: .uploaders,
        keywords: ["Metadata", "EXIF", "GPS", "Location", "Privacy", "Strip", "Camera"], anchor: "uploaders.imageMetadata"
    )
}

struct ImageOptimizationOverrideSection: View {
    @Binding var override: ImageOptimizationOverride

    var body: some View {
        Section {
            Picker("Optimize images".localized(), selection: $override.enabled) {
                Text("Use the global setting".localized()).tag(Bool?.none)
                Text("On".localized()).tag(Bool?.some(true))
                Text("Off".localized()).tag(Bool?.some(false))
            }
            Picker("Image format".localized(), selection: $override.format) {
                Text("Use the global setting".localized()).tag(ImageOptimizationFormat?.none)
                ForEach(ImageOptimizationFormat.allCases) { format in
                    Text(format.titleKey.localized()).tag(ImageOptimizationFormat?.some(format))
                }
            }
            Text("Some hosts reject AVIF or WebP. Choose “Keep the format” for them.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Image Optimization".localized())
        }
    }
}
