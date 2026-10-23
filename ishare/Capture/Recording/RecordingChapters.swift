import AVFoundation
import CoreMedia
import Foundation

struct RecordingMarker: Hashable, Sendable {
    var time: Double
    var title: String
}

struct RecordingChapter: Hashable, Sendable {
    var title: String
    var start: Double
    var end: Double

    var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    }
}

struct RecordingMarkerLog: Sendable {
    private(set) var times: [Double] = []

    var markers: [RecordingMarker] {
        RecordingChapters.markers(at: times)
    }

    @discardableResult
    mutating func add(at time: Double) -> RecordingMarker {
        times.append(max(0, time))
        times.sort()
        let index = times.lastIndex(of: max(0, time)) ?? times.count - 1
        return RecordingMarker(time: times[index], title: RecordingChapters.markerTitle(index))
    }
}

enum RecordingChapters {
    static let minimumChapterLength: Double = 0.1

    static func markerTitle(_ index: Int) -> String {
        String(format: "Marker %d".localized(), index + 1)
    }

    static var openingTitle: String {
        "Start".localized()
    }

    static func markers(at times: [Double]) -> [RecordingMarker] {
        times.sorted().enumerated().map { RecordingMarker(time: $1, title: markerTitle($0)) }
    }

    static func rebased(_ markers: [RecordingMarker], to range: ClosedRange<Double>) -> [RecordingMarker] {
        markers
            .filter { range.contains($0.time) }
            .map { RecordingMarker(time: $0.time - range.lowerBound, title: $0.title) }
    }

    static func chapters(for markers: [RecordingMarker], duration: Double) -> [RecordingChapter] {
        guard duration > 0 else { return [] }
        var starts: [(time: Double, title: String)] = []
        for marker in markers.sorted(by: { $0.time < $1.time }) where marker.time < duration - minimumChapterLength {
            let time = max(0, marker.time)
            if let last = starts.last, time - last.time < minimumChapterLength {
                starts[starts.count - 1] = (last.time, marker.title)
            } else {
                starts.append((time, marker.title))
            }
        }
        guard !starts.isEmpty else { return [] }
        if starts[0].time >= minimumChapterLength {
            starts.insert((0, openingTitle), at: 0)
        } else {
            starts[0].time = 0
        }
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1].time : duration
            return RecordingChapter(title: start.title, start: start.time, end: end)
        }
    }

    static func write(_ markers: [RecordingMarker], into url: URL) async throws {
        guard !markers.isEmpty else { return }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let chapters = chapters(for: markers, duration: duration)
        guard !chapters.isEmpty else { return }
        let temporaryURL = MediaFiles.siblingTemporaryURL(for: url, tag: "chapters")
        do {
            try await ChapterRemuxer.remux(asset, chapters: chapters, to: temporaryURL, fileType: VideoTrimmer.fileType(for: url))
            try MediaFiles.replace(url, with: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func read(from url: URL) async throws -> [RecordingChapter] {
        let asset = AVURLAsset(url: url)
        let locales = try await asset.load(.availableChapterLocales)
        guard let locale = locales.first else { return [] }
        let groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])
        var chapters: [RecordingChapter] = []
        for group in groups {
            let title = try await group.items.first?.load(.stringValue) ?? ""
            chapters.append(RecordingChapter(title: title, start: group.timeRange.start.seconds, end: group.timeRange.end.seconds))
        }
        return chapters
    }
}

enum ChapterTextSample {
    private static let utf8EncodingAtom: [UInt8] = [0, 0, 0, 12, 0x65, 0x6E, 0x63, 0x64, 0, 0, 1, 0]

    static func payload(for title: String) -> Data {
        let text = Array(title.utf8.prefix(Int(UInt16.max)))
        var data = Data([UInt8(text.count >> 8), UInt8(text.count & 0xFF)])
        data.append(contentsOf: text)
        data.append(contentsOf: utf8EncodingAtom)
        return data
    }

    static func formatDescription() -> CMFormatDescription? {
        let white: [String: Any] = [
            kCMTextFormatDescriptionColor_Red as String: 255,
            kCMTextFormatDescriptionColor_Green as String: 255,
            kCMTextFormatDescriptionColor_Blue as String: 255,
            kCMTextFormatDescriptionColor_Alpha as String: 255,
        ]
        let black: [String: Any] = [
            kCMTextFormatDescriptionColor_Red as String: 0,
            kCMTextFormatDescriptionColor_Green as String: 0,
            kCMTextFormatDescriptionColor_Blue as String: 0,
            kCMTextFormatDescriptionColor_Alpha as String: 255,
        ]
        let extensions: [String: Any] = [
            kCMTextFormatDescriptionExtension_DisplayFlags as String: 0,
            kCMTextFormatDescriptionExtension_BackgroundColor as String: black,
            kCMTextFormatDescriptionExtension_DefaultTextBox as String: [
                kCMTextFormatDescriptionRect_Top as String: 0,
                kCMTextFormatDescriptionRect_Left as String: 0,
                kCMTextFormatDescriptionRect_Bottom as String: 0,
                kCMTextFormatDescriptionRect_Right as String: 0,
            ],
            kCMTextFormatDescriptionExtension_DefaultStyle as String: [
                kCMTextFormatDescriptionStyle_StartChar as String: 0,
                kCMTextFormatDescriptionStyle_EndChar as String: 0,
                kCMTextFormatDescriptionStyle_Font as String: 1,
                kCMTextFormatDescriptionStyle_FontFace as String: 0,
                kCMTextFormatDescriptionStyle_ForegroundColor as String: white,
                kCMTextFormatDescriptionStyle_FontSize as String: 12,
            ],
            kCMTextFormatDescriptionExtension_HorizontalJustification as String: 0,
            kCMTextFormatDescriptionExtension_VerticalJustification as String: 0,
            kCMTextFormatDescriptionExtension_FontTable as String: ["1": "Sans-Serif"],
        ]
        var description: CMFormatDescription?
        let status = CMFormatDescriptionCreate(allocator: nil, mediaType: kCMMediaType_Text, mediaSubType: kCMTextFormatType_3GText, extensions: extensions as CFDictionary, formatDescriptionOut: &description)
        return status == noErr ? description : nil
    }

    static func sampleBuffer(for chapter: RecordingChapter, format: CMFormatDescription) -> CMSampleBuffer? {
        let data = payload(for: chapter.title)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block
        else { return nil }
        let copied = data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: chapter.timeRange.duration, presentationTimeStamp: chapter.timeRange.start, decodeTimeStamp: .invalid)
        var size = data.count
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sampleBuffer)
        return status == noErr ? sampleBuffer : nil
    }
}

enum ChapterRemuxer {
    static func remux(_ asset: AVAsset, chapters: [RecordingChapter], to outputURL: URL, fileType: AVFileType) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        let duration = try await asset.load(.duration)
        var lanes: [MediaPumpLane] = []
        var primaryInput: AVAssetWriterInput?
        for track in try await asset.load(.tracks) where track.mediaType == .video || track.mediaType == .audio {
            let formatHint = try await track.load(.formatDescriptions).first
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { continue }
            reader.add(output)
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: formatHint)
            input.expectsMediaDataInRealTime = false
            if track.mediaType == .video {
                input.transform = try await track.load(.preferredTransform)
            }
            guard writer.canAdd(input) else { continue }
            writer.add(input)
            if primaryInput?.mediaType != .video {
                primaryInput = input
            }
            lanes.append(MediaPumpLane(output: output, input: input))
        }
        guard let primaryInput, let format = ChapterTextSample.formatDescription() else { throw MediaPumpError.writerFailed(nil) }
        let chapterInput = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        chapterInput.expectsMediaDataInRealTime = false
        chapterInput.marksOutputTrackAsEnabled = false
        chapterInput.languageCode = "und"
        guard writer.canAdd(chapterInput) else { throw MediaPumpError.writerFailed(nil) }
        writer.add(chapterInput)
        primaryInput.addTrackAssociation(withTrackOf: chapterInput, type: AVAssetTrack.AssociationType.chapterList.rawValue)

        let range = CMTimeRange(start: .zero, duration: duration)
        try await MediaPump.run(reader: reader, writer: writer, lanes: lanes, timeRange: range, prepareSession: { _ in
            for chapter in chapters {
                if let sample = ChapterTextSample.sampleBuffer(for: chapter, format: format) {
                    chapterInput.append(sample)
                }
            }
            chapterInput.markAsFinished()
        })
    }
}
