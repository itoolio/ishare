@preconcurrency import AppKit
import AVFoundation
import BezelNotification
import Defaults
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
enum RecordingFlow {
    static func recordingURL() -> URL {
        let suffix = NSWorkspace.shared.frontmostApplication?.localizedName ?? "screen"
        let ext = Defaults[.recordMP4] ? "mp4" : "mov"
        let fileName = CaptureFileName.make(prefix: Defaults[.recordingFileName], suffix: suffix, ext: ext)
        return SaveLocation.fileURL(for: .recordings, fileName: fileName)
    }
}

enum GIFExportError: LocalizedError {
    case noVideoTrack
    case destinationUnavailable
    case finalizeFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track found in the recording"
        case .destinationUnavailable: "Couldn't create the GIF file"
        case .finalizeFailed: "GIF export failed"
        }
    }
}

func exportGif(from videoURL: URL, frameRate: Int, maxPixelSize: CGFloat? = nil, deleteSource: Bool = true) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)
    let duration = try await asset.load(.duration).seconds
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw GIFExportError.noVideoTrack }
    let naturalSize = try await track.load(.naturalSize)
    let times = GIFTiming.frameTimes(duration: duration, frameRate: frameRate)

    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = CMTime(seconds: GIFTiming.delay(frameRate: frameRate) / 2, preferredTimescale: 600)
    generator.appliesPreferredTrackTransform = true
    if let maxPixelSize {
        let scale = min(1, maxPixelSize / max(naturalSize.width, naturalSize.height))
        generator.maximumSize = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
    }

    let outputURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
        throw GIFExportError.destinationUnavailable
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: GIFTiming.delay(frameRate: frameRate)]] as CFDictionary

    var lastImage: CGImage?
    for await result in generator.images(for: times) {
        if let image = (try? result.image) ?? lastImage {
            CGImageDestinationAddImage(destination, image, frameProperties)
            lastImage = image
        }
    }
    guard CGImageDestinationFinalize(destination) else { throw GIFExportError.finalizeFailed }
    if deleteSource {
        try? FileManager.default.removeItem(at: videoURL)
    }
    return outputURL
}
