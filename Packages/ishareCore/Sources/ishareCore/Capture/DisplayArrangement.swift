import CoreGraphics
import Foundation

public struct DisplayPlacement: Equatable, Sendable {
    public var id: UInt32
    public var pixelRect: CGRect
}

public struct DisplayArrangement: Equatable, Sendable {
    public var pixelSize: CGSize
    public var placements: [DisplayPlacement]

    public static func layout(frames: [(id: UInt32, frame: CGRect)], scale: CGFloat) -> DisplayArrangement? {
        guard let first = frames.first?.frame, scale > 0 else { return nil }
        let union = frames.dropFirst().reduce(first) { $0.union($1.frame) }
        let placements = frames.map { entry in
            DisplayPlacement(
                id: entry.id,
                pixelRect: CGRect(
                    x: ((entry.frame.minX - union.minX) * scale).rounded(), y: ((entry.frame.minY - union.minY) * scale).rounded(),
                    width: (entry.frame.width * scale).rounded(), height: (entry.frame.height * scale).rounded()))
        }
        return DisplayArrangement(pixelSize: CGSize(width: (union.width * scale).rounded(), height: (union.height * scale).rounded()), placements: placements)
    }
}
