import AVFoundation
import Defaults
import Foundation
import ishareCore

enum VoiceOverMode: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case mix
    case duck
    case replace

    var id: Self { self }

    var title: String {
        switch self {
        case .mix: "Mix with the original audio"
        case .duck: "Lower the original audio while speaking"
        case .replace: "Replace the original audio"
        }
    }
}

struct VoiceOverClip: Hashable, Sendable {
    var url: URL
    var videoTime: Double
    var duration: Double

    var end: Double { videoTime + duration }
}

struct VoiceOverMix: Hashable, Sendable {
    var clips: [VoiceOverClip]
    var mode: VoiceOverMode
    var ducking: DuckingSettings
    var voiceLevels: LevelSeries?

    func originalGainPoints(duration: Double) -> [GainPoint] {
        switch mode {
        case .mix:
            return []
        case .replace:
            return [GainPoint(time: 0, gain: 0)]
        case .duck:
            guard let voiceLevels else { return [] }
            return DuckingEnvelope.points(levels: voiceLevels, settings: ducking, duration: duration)
        }
    }
}

struct RecordingEdit: Hashable, Sendable {
    var plan: RetimingPlan
    var voiceOver: VoiceOverMix?

    var needsReencoding: Bool { plan.hasSpeedChanges || voiceOver != nil }

    var isNoOp: Bool { plan.isIdentity && voiceOver == nil }
}

enum RecordingEditError: LocalizedError {
    case nothingLeft

    var errorDescription: String? {
        switch self {
        case .nothingLeft: "Nothing is left of the recording after cutting the silent parts.".localized()
        }
    }
}

struct EditedComposition: @unchecked Sendable {
    let composition: AVMutableComposition
    let audioMix: AVAudioMix?
}

enum RecordingEditor {
    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    static func composition(for asset: AVAsset, edit: RecordingEdit) async throws -> EditedComposition {
        let composition = AVMutableComposition()
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
            let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw RecordingExportError.noVideoTrack }
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio)
        let audioTracks = sourceAudio.compactMap { _ in composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }

        var cursor = CMTime.zero
        for segment in edit.plan.segments {
            guard let rate = segment.action.rate else { continue }
            let range = CMTimeRange(start: time(segment.start), end: time(segment.end)).intersection(fullRange)
            guard range.duration > .zero else { continue }
            try video.insertTimeRange(range, of: sourceVideo, at: cursor)
            for (source, destination) in zip(sourceAudio, audioTracks) {
                if segment.action.keepsAudio {
                    try destination.insertTimeRange(range, of: source, at: cursor)
                } else {
                    destination.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: range.duration))
                }
            }
            if rate > 1 {
                let scaled = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / rate)
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: scaled)
                cursor = cursor + scaled
            } else {
                cursor = cursor + range.duration
            }
        }
        guard cursor > .zero else { throw RecordingEditError.nothingLeft }

        var parameters: [AVMutableAudioMixInputParameters] = []
        if let voiceOver = edit.voiceOver {
            try await insertVoiceOver(voiceOver, plan: edit.plan, into: composition)
            let points = voiceOver.originalGainPoints(duration: duration.seconds)
            parameters = audioTracks.map { track in
                let input = AVMutableAudioMixInputParameters(track: track)
                applyGain(points, plan: edit.plan, to: input)
                return input
            }
        }
        let audioMix: AVMutableAudioMix? = parameters.isEmpty ? nil : AVMutableAudioMix()
        audioMix?.inputParameters = parameters
        return EditedComposition(composition: composition, audioMix: audioMix)
    }

    private static func insertVoiceOver(_ voiceOver: VoiceOverMix, plan: RetimingPlan, into composition: AVMutableComposition) async throws {
        for clip in voiceOver.clips {
            let clipAsset = AVURLAsset(url: clip.url)
            guard let source = try await clipAsset.loadTracks(withMediaType: .audio).first,
                let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let clipDuration = min(clip.duration, try await clipAsset.load(.duration).seconds)
            for segment in plan.segments where segment.action.keepsAudio {
                let start = max(segment.start, clip.videoTime)
                let end = min(segment.end, clip.videoTime + clipDuration)
                guard end - start > 0.01, let destination = plan.outputTime(forSource: start) else { continue }
                let range = CMTimeRange(start: time(start - clip.videoTime), end: time(end - clip.videoTime))
                try track.insertTimeRange(range, of: source, at: time(destination))
            }
            if track.segments.isEmpty { composition.removeTrack(track) }
        }
    }

    static func applyGain(_ points: [GainPoint], plan: RetimingPlan, to input: AVMutableAudioMixInputParameters) {
        let mapped = points.compactMap { point in plan.outputTime(forSource: point.time).map { GainPoint(time: $0, gain: point.gain) } }
        guard let first = mapped.first else { return }
        input.setVolume(Float(first.gain), at: .zero)
        for (previous, next) in zip(mapped, mapped.dropFirst()) {
            if next.time - previous.time > 0.001 {
                input.setVolumeRamp(
                    fromStartVolume: Float(previous.gain), toEndVolume: Float(next.gain), timeRange: CMTimeRange(start: time(previous.time), end: time(next.time)))
            } else {
                input.setVolume(Float(next.gain), at: time(next.time))
            }
        }
    }

    static func render(_ url: URL, edit: RecordingEdit, to outputURL: URL, hevc: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let asset = AVURLAsset(url: url)
        let edited = try await composition(for: asset, edit: edit)
        let preset = edit.needsReencoding ? (hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality) : AVAssetExportPresetPassthrough
        try await CompositionExport.export(edited, preset: preset, to: outputURL, fileType: VideoTrimmer.fileType(for: outputURL), progress: progress)
    }

    static func renderInPlace(_ url: URL, edit: RecordingEdit, hevc: Bool, progress: (@Sendable (Double) -> Void)?) async throws -> URL {
        let temporaryURL = MediaFiles.siblingTemporaryURL(for: url, tag: "edit")
        do {
            try await render(url, edit: edit, to: temporaryURL, hevc: hevc, progress: progress)
            try MediaFiles.replace(url, with: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        return url
    }
}

enum CompositionExport {
    static func export(_ edited: EditedComposition, preset: String, to outputURL: URL, fileType: AVFileType, progress: (@Sendable (Double) -> Void)?) async throws {
        guard let session = AVAssetExportSession(asset: edited.composition, presetName: preset) else { throw VideoTrimError.exportUnavailable }
        session.audioMix = edited.audioMix
        try? FileManager.default.removeItem(at: outputURL)
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
        try await session.export(to: outputURL, as: fileType)
        progress?(1)
    }
}

extension RecordingChapters {
    static func retimed(_ markers: [RecordingMarker], through plan: RetimingPlan) -> [RecordingMarker] {
        markers.compactMap { marker in
            plan.outputTime(forSource: marker.time).map { RecordingMarker(time: $0, title: marker.title) }
        }
    }
}
