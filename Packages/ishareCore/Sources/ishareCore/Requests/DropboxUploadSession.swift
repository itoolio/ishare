import Foundation

public enum DropboxUploadStep: Equatable, Sendable {
    case start(Range<Int>)
    case append(Range<Int>)
    case finish(Range<Int>)

    public var range: Range<Int> {
        switch self {
        case let .start(range), let .append(range), let .finish(range): range
        }
    }
}

public enum DropboxUploadSession {
    public static let singleRequestLimit = 150 * 1024 * 1024
    public static let defaultChunkSize = 16 * 1024 * 1024
    public static let maximumOffsetCorrections = 8

    public static func usesSession(size: Int, limit: Int = singleRequestLimit) -> Bool {
        size > limit
    }

    public static func nextStep(offset: Int, size: Int, chunkSize: Int = defaultChunkSize, started: Bool) -> DropboxUploadStep {
        let chunk = max(chunkSize, 1)
        guard started else { return .start(0 ..< min(chunk, size)) }
        let start = min(max(offset, 0), size)
        let remaining = size - start
        return remaining > chunk ? .append(start ..< start + chunk) : .finish(start ..< size)
    }

    public static func plan(size: Int, chunkSize: Int = defaultChunkSize) -> [DropboxUploadStep] {
        var steps: [DropboxUploadStep] = []
        var offset = 0
        var started = false
        while true {
            let step = nextStep(offset: offset, size: size, chunkSize: chunkSize, started: started)
            steps.append(step)
            if case .finish = step { return steps }
            started = true
            offset = step.range.upperBound
        }
    }

    public static func startArgument() -> [String: Any] {
        ["close": false]
    }

    public static func appendArgument(sessionID: String, offset: Int) -> [String: Any] {
        ["cursor": ["session_id": sessionID, "offset": offset], "close": false]
    }

    public static func finishArgument(sessionID: String, offset: Int, path: String) -> [String: Any] {
        [
            "cursor": ["session_id": sessionID, "offset": offset],
            "commit": ["path": path, "mode": "add", "autorename": true, "mute": true],
        ]
    }

    public static func correctOffset(fromErrorBody body: String?) -> Int? {
        guard let body, let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) else { return nil }
        return correctOffset(in: object)
    }

    static func correctOffset(in value: Any) -> Int? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let offset = dictionary["correct_offset"] as? NSNumber {
            return offset.intValue
        }
        for nested in dictionary.values {
            if let offset = correctOffset(in: nested) {
                return offset
            }
        }
        return nil
    }
}
