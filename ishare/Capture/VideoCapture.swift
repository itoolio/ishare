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

@MainActor
func recordScreen(gif: Bool = false, region: Bool = false, forceUpload: Bool = false) {
    let recorder = AppDelegate.shared.screenRecorder
    guard !recorder.isRunning else {
        AppDelegate.shared.stopRecording()
        return
    }
    AppDelegate.shared.recordGif = gif
    AppDelegate.shared.forceUploadRecording = forceUpload
    Task { @MainActor in
        guard await recorder.canRecord else {
            BezelNotification.show(messageText: "Missing permission".localized(), icon: ToastIcon)
            return
        }
        let fileURL = RecordingFlow.recordingURL()
        if region {
            let outcome = await RegionSelector.select(options: .init(showsMagnifier: false, allowsWindowMode: false, hint: "Select the area to record".localized()))
            switch outcome {
            case let .region(screen, rect):
                await recorder.start(fileURL, target: .region(screen, rect))
            case let .fullScreen(screen):
                await recorder.start(fileURL, target: .region(screen, CGRect(origin: .zero, size: screen.frame.size)))
            case .switchToWindow, .cancelled:
                return
            }
        } else {
            await recorder.start(fileURL, target: .picker)
        }
    }
}

@MainActor
func postRecordingTasks(_ url: URL, _ recordGif: Bool, forceUpload: Bool = false) {
    Task { @MainActor in
        var fileURL = url
        if recordGif {
            do {
                fileURL = try await exportGif(from: url, frameRate: Defaults[.gifFrameRate].rawValue)
            } catch {
                NSLog("GIF export failed: %@", error.localizedDescription)
                BezelNotification.show(messageText: "GIF export failed".localized(), icon: ToastIcon)
            }
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        await PostCapture.handle(fileURL: fileURL, kind: .video, forceUpload: forceUpload)
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
