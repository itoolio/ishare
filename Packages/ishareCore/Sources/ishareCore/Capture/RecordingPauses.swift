import Foundation

public struct RecordingMediaSegment: Hashable, Sendable {
    public var sourceStart: Double
    public var outputStart: Double
    public var duration: Double

    public init(sourceStart: Double, outputStart: Double, duration: Double) {
        self.sourceStart = sourceStart
        self.outputStart = outputStart
        self.duration = duration
    }
}

public struct RecordingPauseTimeline: Hashable, Sendable {
    public private(set) var pauses: [Range<Double>]
    public private(set) var pausedSince: Double?

    public init(pauses: [Range<Double>] = [], pausedSince: Double? = nil) {
        self.pauses = pauses.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
        self.pausedSince = pausedSince
    }

    public var isPaused: Bool { pausedSince != nil }

    public var isEmpty: Bool { pauses.isEmpty && pausedSince == nil }

    @discardableResult
    public mutating func pause(at time: Double) -> Bool {
        guard pausedSince == nil else { return false }
        pausedSince = max(time, pauses.last?.upperBound ?? time)
        return true
    }

    @discardableResult
    public mutating func resume(at time: Double) -> Bool {
        guard let since = pausedSince else { return false }
        pausedSince = nil
        if time > since {
            pauses.append(since ..< time)
        }
        return true
    }

    public func closed(at time: Double) -> RecordingPauseTimeline {
        var copy = self
        copy.resume(at: time)
        return copy
    }

    public func allPauses(until now: Double) -> [Range<Double>] {
        guard let pausedSince else { return pauses }
        return pauses + (now > pausedSince ? [pausedSince ..< now] : [])
    }

    public func pausedDuration(from start: Double, to time: Double) -> Double {
        guard time > start else { return 0 }
        return allPauses(until: time).reduce(0) { total, pause in
            let lower = max(pause.lowerBound, start)
            let upper = min(pause.upperBound, time)
            return total + max(0, upper - lower)
        }
    }

    public func recordedDuration(from start: Double, to time: Double) -> Double {
        max(0, time - start - pausedDuration(from: start, to: time))
    }

    public func isPaused(at time: Double) -> Bool {
        if let pausedSince, time >= pausedSince { return true }
        return pauses.contains { $0.contains(time) }
    }

    public func outputTime(of time: Double, recordingStart start: Double) -> Double? {
        guard time >= start else { return time - start }
        guard !isPaused(at: time) else { return nil }
        return time - start - pausedDuration(from: start, to: time)
    }

    public func recordedSpans(from start: Double) -> [(start: Double, end: Double)] {
        var spans: [(start: Double, end: Double)] = []
        var cursor = start
        for pause in pauses where pause.upperBound > start {
            if pause.lowerBound > cursor {
                spans.append((cursor, pause.lowerBound))
            }
            cursor = max(cursor, pause.upperBound)
        }
        if let pausedSince {
            if pausedSince > cursor { spans.append((cursor, pausedSince)) }
        } else {
            spans.append((cursor, .infinity))
        }
        return spans
    }

    public func segments(sourceStart clipStart: Double, sourceDuration: Double, recordingStart start: Double, outputDuration: Double) -> [RecordingMediaSegment] {
        guard sourceDuration > 0, outputDuration > 0 else { return [] }
        let clipEnd = clipStart + sourceDuration
        var outputCursor = 0.0
        var segments: [RecordingMediaSegment] = []
        for span in recordedSpans(from: start) {
            let spanOutputStart = outputCursor
            let available = outputDuration - spanOutputStart
            guard available > 0 else { break }
            let lower = max(span.start, clipStart)
            let upper = min(span.end, clipEnd, span.start + available)
            if upper > lower {
                segments.append(RecordingMediaSegment(sourceStart: lower - clipStart, outputStart: spanOutputStart + (lower - span.start), duration: upper - lower))
            }
            outputCursor += span.end - span.start
        }
        return segments
    }
}
