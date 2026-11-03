import Testing
@testable import ishareCore

struct FrameRingTests {
    @Test func dropsFramesOlderThanTheWindow() {
        var ring = FrameRing<Int>(maximumAge: 10, maximumBytes: .max)
        for second in 0 ... 15 {
            ring.append(second, at: Double(second), bytes: 1)
        }
        #expect(ring.entries.map(\.frame) == Array(5 ... 15))
    }

    @Test func dropsTheOldestFramesWhenOverTheMemoryBudget() {
        var ring = FrameRing<Int>(maximumAge: 100, maximumBytes: 250)
        for index in 0 ..< 5 {
            ring.append(index, at: Double(index), bytes: 100)
        }
        #expect(ring.entries.map(\.frame) == [3, 4])
        #expect(ring.totalBytes == 200)
    }

    @Test func alwaysKeepsTheNewestFrame() {
        var ring = FrameRing<Int>(maximumAge: 100, maximumBytes: 10)
        ring.append(1, at: 0, bytes: 50)
        #expect(ring.entries.map(\.frame) == [1])
        ring.removeAll()
        #expect(ring.entries.isEmpty)
    }
}
