import Foundation
import Testing
@testable import ishareCore

struct WatchFolderUndoTests {
    @Test func undoesMovesInReverseOrder() {
        let run = WatchFolderRun(date: Date(), moves: [WatchFolderMove(from: "/w/a.png", to: "/w/b.png"), WatchFolderMove(from: "/w/b.png", to: "/done/b.png")])
        #expect(run.undoMoves == [WatchFolderMove(from: "/done/b.png", to: "/w/b.png"), WatchFolderMove(from: "/w/b.png", to: "/w/a.png")])
        #expect(run.fileName == "a.png")
    }

    @Test func keepsTheLatestRunsWithMoves() {
        var log = WatchFolderUndoLog()
        log.record(WatchFolderRun(date: Date(), moves: []))
        #expect(log.runs.isEmpty)
        for index in 0 ..< 25 {
            log.record(WatchFolderRun(date: Date(), moves: [WatchFolderMove(from: "/w/\(index)", to: "/x/\(index)")]))
        }
        #expect(log.runs.count == WatchFolderUndoLog.limit)
        #expect(log.last?.moves.first?.from == "/w/24")
        #expect(log.popLast()?.moves.first?.from == "/w/24")
        #expect(log.last?.moves.first?.from == "/w/23")
    }
}
