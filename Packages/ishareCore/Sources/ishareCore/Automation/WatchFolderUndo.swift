import Foundation

public struct WatchFolderMove: Codable, Hashable, Sendable {
    public var from: String
    public var to: String
    public var folderBookmark: Data?

    public init(from: String, to: String, folderBookmark: Data? = nil) {
        self.from = from
        self.to = to
        self.folderBookmark = folderBookmark
    }

    public var reversed: WatchFolderMove {
        WatchFolderMove(from: to, to: from, folderBookmark: folderBookmark)
    }
}

public struct WatchFolderRun: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var moves: [WatchFolderMove]

    public init(id: UUID = UUID(), date: Date, moves: [WatchFolderMove]) {
        self.id = id
        self.date = date
        self.moves = moves
    }

    public var undoMoves: [WatchFolderMove] {
        moves.reversed().map(\.reversed)
    }

    public var fileName: String {
        URL(fileURLWithPath: moves.first?.from ?? "").lastPathComponent
    }
}

public struct WatchFolderUndoLog: Codable, Hashable, Sendable {
    public static let limit = 20

    public private(set) var runs: [WatchFolderRun]

    public init(runs: [WatchFolderRun] = []) {
        self.runs = runs
    }

    public var last: WatchFolderRun? {
        runs.last
    }

    public mutating func record(_ run: WatchFolderRun) {
        guard !run.moves.isEmpty else { return }
        runs.append(run)
        if runs.count > Self.limit {
            runs.removeFirst(runs.count - Self.limit)
        }
    }

    @discardableResult
    public mutating func popLast() -> WatchFolderRun? {
        runs.popLast()
    }
}
