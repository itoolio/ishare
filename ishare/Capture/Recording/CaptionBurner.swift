import AppKit
import AVFoundation
import QuartzCore

enum CaptionStyle {
    static func fontSize(forRenderHeight height: CGFloat) -> CGFloat {
        max(16, (height * 0.045).rounded())
    }

    static func bottomMargin(forRenderHeight height: CGFloat) -> CGFloat {
        max(12, (height * 0.06).rounded())
    }

    static func attributedText(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
    }

    static func boxFrame(for textSize: CGSize, fontSize: CGFloat, renderSize: CGSize) -> CGRect {
        let horizontalPadding = fontSize * 0.6
        let verticalPadding = fontSize * 0.3
        let width = min(renderSize.width - 16, textSize.width + horizontalPadding * 2)
        let height = textSize.height + verticalPadding * 2
        return CGRect(x: (renderSize.width - width) / 2, y: bottomMargin(forRenderHeight: renderSize.height), width: width, height: height)
    }
}

enum CaptionBurner {
    static func overlayLayer(for cues: [CaptionCue], renderSize: CGSize) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: renderSize)
        let fontSize = CaptionStyle.fontSize(forRenderHeight: renderSize.height)
        for cue in cues where cue.end > cue.start {
            container.addSublayer(cueLayer(cue, fontSize: fontSize, renderSize: renderSize))
        }
        return container
    }

    private static func cueLayer(_ cue: CaptionCue, fontSize: CGFloat, renderSize: CGSize) -> CALayer {
        let text = CaptionStyle.attributedText(cue.text, fontSize: fontSize)
        let bounds = text.boundingRect(with: CGSize(width: renderSize.width - 32, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textSize = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        let box = CALayer()
        box.frame = CaptionStyle.boxFrame(for: textSize, fontSize: fontSize, renderSize: renderSize)
        box.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
        box.cornerRadius = fontSize * 0.35
        box.opacity = 0

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.isWrapped = true
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 1
        textLayer.frame = CGRect(x: (box.bounds.width - textSize.width) / 2, y: (box.bounds.height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        box.addSublayer(textLayer)

        let visibility = CABasicAnimation(keyPath: "opacity")
        visibility.fromValue = 1
        visibility.toValue = 1
        visibility.beginTime = cue.start <= 0 ? AVCoreAnimationBeginTimeAtZero : cue.start
        visibility.duration = cue.end - cue.start
        visibility.isRemovedOnCompletion = false
        visibility.fillMode = .removed
        box.add(visibility, forKey: "visibility")
        return box
    }

    static func burn(_ cues: [CaptionCue], into url: URL, hevc: Bool, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard !cues.isEmpty else { return }
        let asset = AVURLAsset(url: url)
        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        let renderSize = composition.renderSize
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)
        parent.addSublayer(overlayLayer(for: cues, renderSize: renderSize))
        composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        try await VideoCompositionExporter.export(asset, videoComposition: composition, replacing: url, hevc: hevc, progress: progress)
    }
}

enum VideoCompositionExporter {
    static func export(_ asset: AVAsset, videoComposition: AVVideoComposition, replacing url: URL, hevc: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let preset = hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw VideoTrimError.exportUnavailable }
        session.videoComposition = videoComposition
        let temporaryURL = MediaFiles.siblingTemporaryURL(for: url, tag: "render")
        nonisolated(unsafe) let monitoredSession = session
        let monitor = progress.map { report in
            Task {
                for await state in monitoredSession.states(updateInterval: 0.2) {
                    if case let .exporting(exportProgress) = state {
                        report(exportProgress.fractionCompleted)
                    }
                }
            }
        }
        defer { monitor?.cancel() }
        do {
            try await session.export(to: temporaryURL, as: VideoTrimmer.fileType(for: url))
            try MediaFiles.replace(url, with: temporaryURL)
            progress?(1)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }
}
