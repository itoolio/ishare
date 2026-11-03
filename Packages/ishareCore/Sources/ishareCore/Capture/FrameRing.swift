import Foundation

public struct FrameRing<Frame: Sendable>: Sendable {
    public struct Entry: Sendable {
        public var time: Double
        public var frame: Frame
        public var bytes: Int
    }

    public private(set) var entries: [Entry] = []
    public var maximumAge: Double
    public var maximumBytes: Int

    public init(maximumAge: Double, maximumBytes: Int) {
        self.maximumAge = maximumAge
        self.maximumBytes = maximumBytes
    }

    public var totalBytes: Int {
        entries.reduce(0) { $0 + $1.bytes }
    }

    public mutating func append(_ frame: Frame, at time: Double, bytes: Int) {
        entries.append(Entry(time: time, frame: frame, bytes: bytes))
        trim(now: time)
    }

    public mutating func trim(now: Double) {
        entries.removeAll { now - $0.time > maximumAge }
        var total = totalBytes
        while total > maximumBytes, entries.count > 1 {
            total -= entries.removeFirst().bytes
        }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
