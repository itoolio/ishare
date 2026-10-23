@preconcurrency import AVFoundation
import Foundation

enum MediaPumpError: LocalizedError {
    case readerFailed(String?)
    case writerFailed(String?)

    var errorDescription: String? {
        switch self {
        case let .readerFailed(reason): reason ?? "The recording couldn't be read"
        case let .writerFailed(reason): reason ?? "The recording couldn't be written"
        }
    }
}

struct MediaPumpLane: @unchecked Sendable {
    let output: AVAssetReaderOutput
    let input: AVAssetWriterInput
}

private final class MediaPumpSession: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let lanes: [MediaPumpLane]
    let duration: Double
    let startTime: Double
    let progress: (@Sendable (Double) -> Void)?
    private let lock = NSLock()
    private var reportedProgress: Double = 0

    init(reader: AVAssetReader, writer: AVAssetWriter, lanes: [MediaPumpLane], startTime: Double, duration: Double, progress: (@Sendable (Double) -> Void)?) {
        self.reader = reader
        self.writer = writer
        self.lanes = lanes
        self.startTime = startTime
        self.duration = duration
        self.progress = progress
    }

    func report(_ time: CMTime) {
        guard let progress, duration > 0, time.isNumeric else { return }
        let value = min(max((time.seconds - startTime) / duration, 0), 1)
        let shouldReport = lock.withLock {
            guard value - reportedProgress >= 0.01 else { return false }
            reportedProgress = value
            return true
        }
        if shouldReport { progress(value) }
    }
}

enum MediaPump {
    static func run(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        lanes: [MediaPumpLane],
        timeRange: CMTimeRange,
        prepareSession: (AVAssetWriter) -> Void = { _ in },
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard reader.startReading() else { throw MediaPumpError.readerFailed(reader.error?.localizedDescription) }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw MediaPumpError.writerFailed(writer.error?.localizedDescription)
        }
        writer.startSession(atSourceTime: timeRange.start)
        prepareSession(writer)
        let session = MediaPumpSession(reader: reader, writer: writer, lanes: lanes, startTime: timeRange.start.seconds, duration: timeRange.duration.seconds, progress: progress)
        await pump(session)
        if reader.status == .failed {
            writer.cancelWriting()
            throw MediaPumpError.readerFailed(reader.error?.localizedDescription)
        }
        writer.endSession(atSourceTime: timeRange.end)
        await writer.finishWriting()
        guard writer.status == .completed else { throw MediaPumpError.writerFailed(writer.error?.localizedDescription) }
        progress?(1)
    }

    private static func pump(_ session: MediaPumpSession) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for (index, lane) in session.lanes.enumerated() {
                group.enter()
                let queue = DispatchQueue(label: "dev.adrian.ishare.MediaPump.\(index)")
                let finished = LaneCompletion()
                lane.input.requestMediaDataWhenReady(on: queue) {
                    while lane.input.isReadyForMoreMediaData {
                        guard session.writer.status == .writing,
                              let buffer = lane.output.copyNextSampleBuffer()
                        else {
                            lane.input.markAsFinished()
                            if finished.markFinished() { group.leave() }
                            return
                        }
                        session.report(buffer.presentationTimeStamp)
                        if !lane.input.append(buffer) {
                            lane.input.markAsFinished()
                            if finished.markFinished() { group.leave() }
                            return
                        }
                    }
                }
            }
            group.notify(queue: .global()) { continuation.resume() }
        }
    }
}

private final class LaneCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false

    func markFinished() -> Bool {
        lock.withLock {
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
    }
}

enum MediaFiles {
    static func siblingTemporaryURL(for url: URL, extension pathExtension: String? = nil, tag: String) -> URL {
        url.deletingLastPathComponent()
            .appending(path: ".\(url.deletingPathExtension().lastPathComponent)-\(tag)-\(UUID().uuidString).\(pathExtension ?? url.pathExtension)", directoryHint: .notDirectory)
    }

    static func replace(_ url: URL, with temporaryURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }

    static func uniqueURL(for url: URL, extension pathExtension: String, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        var candidate = directory.appending(path: "\(baseName).\(pathExtension)", directoryHint: .notDirectory)
        var index = 2
        while fileExists(candidate) {
            candidate = directory.appending(path: "\(baseName)-\(index).\(pathExtension)", directoryHint: .notDirectory)
            index += 1
        }
        return candidate
    }
}
