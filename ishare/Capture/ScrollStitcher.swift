import CoreGraphics
import Foundation

struct GrayFrame: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

enum ScrollStitcher {
    struct Match: Equatable {
        let offset: Int
        let score: Double
    }

    static let matchThreshold = 8.0

    static func score(previous: GrayFrame, next: GrayFrame, offset: Int, rowStep: Int, columnStep: Int, ignoreTop: Int, ignoreBottom: Int) -> Double {
        let height = min(previous.height, next.height)
        let width = min(previous.width, next.width)
        let firstRow = ignoreTop
        let lastRow = height - offset - ignoreBottom
        guard lastRow - firstRow >= 8 else { return .infinity }
        var total = 0
        var count = 0
        previous.pixels.withUnsafeBufferPointer { prev in
            next.pixels.withUnsafeBufferPointer { nxt in
                var row = firstRow
                while row < lastRow {
                    let prevBase = (row + offset) * previous.width
                    let nextBase = row * next.width
                    var column = 0
                    while column < width {
                        let difference = Int(prev[prevBase + column]) - Int(nxt[nextBase + column])
                        total += difference < 0 ? -difference : difference
                        count += 1
                        column += columnStep
                    }
                    row += rowStep
                }
            }
        }
        return count == 0 ? .infinity : Double(total) / Double(count)
    }

    static func verticalOffset(previous: GrayFrame, next: GrayFrame) -> Match? {
        let height = min(previous.height, next.height)
        guard height >= 32 else { return nil }
        let ignoreTop = height / 8
        let ignoreBottom = height / 16
        let maxOffset = Int(Double(height) * 0.85)
        let coarseRows = max(1, height / 160)
        let coarseColumns = max(1, previous.width / 160)

        let still = score(previous: previous, next: next, offset: 0, rowStep: coarseRows, columnStep: coarseColumns, ignoreTop: ignoreTop, ignoreBottom: ignoreBottom)
        if still < 1.0 {
            return Match(offset: 0, score: still)
        }

        let coarseStep = max(1, height / 300)
        var best = Match(offset: 0, score: still)
        var offset = coarseStep
        while offset <= maxOffset {
            let value = score(previous: previous, next: next, offset: offset, rowStep: coarseRows, columnStep: coarseColumns, ignoreTop: ignoreTop, ignoreBottom: ignoreBottom)
            if value < best.score {
                best = Match(offset: offset, score: value)
            }
            offset += coarseStep
        }

        let lower = max(1, best.offset - coarseStep)
        let upper = min(maxOffset, best.offset + coarseStep)
        let fineRows = max(1, coarseRows / 2)
        let fineColumns = max(1, coarseColumns / 2)
        var refined = Match(offset: best.offset, score: .infinity)
        if lower <= upper {
            for candidate in lower ... upper {
                let value = score(previous: previous, next: next, offset: candidate, rowStep: fineRows, columnStep: fineColumns, ignoreTop: ignoreTop, ignoreBottom: ignoreBottom)
                if value < refined.score {
                    refined = Match(offset: candidate, score: value)
                }
            }
        }
        guard refined.score <= matchThreshold else { return nil }
        return refined
    }

    static func stitch(frames: [CGImage], offsets: [Int]) -> CGImage? {
        guard let first = frames.first else { return nil }
        let width = first.width
        let frameHeight = first.height
        let appended = zip(frames.dropFirst(), offsets).map { min($0.1, $0.0.height) }.filter { $0 > 0 }
        let totalHeight = frameHeight + appended.reduce(0, +)
        guard let context = CGContext(
            data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(first, in: CGRect(x: 0, y: totalHeight - frameHeight, width: width, height: frameHeight))
        var cursor = frameHeight
        for (frame, offset) in zip(frames.dropFirst(), offsets) {
            let rows = min(offset, frame.height)
            guard rows > 0, let strip = frame.cropping(to: CGRect(x: 0, y: frame.height - rows, width: frame.width, height: rows)) else { continue }
            context.draw(strip, in: CGRect(x: 0, y: totalHeight - cursor - rows, width: width, height: rows))
            cursor += rows
        }
        return context.makeImage()
    }
}
