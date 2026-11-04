@preconcurrency import AVFoundation
import Defaults
import Foundation

enum SeparateTracksExporter {
    static func folderURL(for recording: URL) -> URL {
        recording.deletingLastPathComponent().appending(path: "\(recording.deletingPathExtension().lastPathComponent) Tracks", directoryHint: .isDirectory)
    }

    static func exportIfEnabled(_ url: URL, sidecar: RecordingSidecar) async {
        guard Defaults[.saveSeparateTracks] else { return }
        do {
            let folder = try await export(url, sidecar: sidecar)
            Log.capture.info("Saved separate tracks to \(folder.path, privacy: .public)")
        } catch {
            Log.capture.error("Saving separate tracks failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func export(_ url: URL, sidecar: RecordingSidecar) async throws -> URL {
        let folder = folderURL(for: url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        if let video = try await asset.loadTracks(withMediaType: .video).first {
            try await exportTrack(video, duration: duration, to: folder.appending(path: "Screen.mov"), fileType: .mov, preset: AVAssetExportPresetPassthrough)
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for (index, track) in audioTracks.enumerated() {
            let name = trackName(index: index, count: audioTracks.count, recordsMicrophone: RecordingDefaults[.recordMic])
            try await exportTrack(track, duration: duration, to: folder.appending(path: "\(name).m4a"), fileType: .m4a, preset: AVAssetExportPresetAppleM4A)
        }
        if let appAudio = sidecar.appAudio?.url {
            try copy(appAudio, to: folder.appending(path: "App Audio.\(appAudio.pathExtension.isEmpty ? "m4a" : appAudio.pathExtension)"))
        }
        if let webcam = sidecar.overlay?.webcam?.url ?? sidecar.webcamTrack?.url {
            try copy(webcam, to: folder.appending(path: "Webcam.mov"))
        }
        return folder
    }

    static func trackName(index: Int, count: Int, recordsMicrophone: Bool) -> String {
        if count == 2, recordsMicrophone {
            return index == 0 ? "System Audio" : "Microphone"
        }
        if count == 1 {
            return recordsMicrophone && RecordingAudioSource.current == .none ? "Microphone" : "Audio"
        }
        return "Audio \(index + 1)"
    }

    private static func exportTrack(_ track: AVAssetTrack, duration: CMTime, to url: URL, fileType: AVFileType, preset: String) async throws {
        try? FileManager.default.removeItem(at: url)
        let composition = AVMutableComposition()
        guard let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        try copy.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        if track.mediaType == .video {
            copy.preferredTransform = try await track.load(.preferredTransform)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { return }
        try await session.export(to: url, as: fileType)
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
