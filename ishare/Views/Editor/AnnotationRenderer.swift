import AppKit
import CoreGraphics

enum AnnotationRenderer {
    static func applyingEffects(_ annotations: [Annotation], to base: CGImage) -> CGImage {
        annotations.reduce(base) { image, annotation in
            switch annotation.shape {
            case let .blur(rect):
                ImageProcessing.blur(image, region: rect)
            case let .pixelate(rect):
                ImageProcessing.pixelate(image, region: rect)
            default:
                image
            }
        }
    }

    static func render(base: CGImage, annotations: [Annotation], crop: CGRect?) -> CGImage? {
        let effected = applyingEffects(annotations, to: base)
        let width = effected.width
        let height = effected.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(effected, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(annotations.filter { !$0.isEffect }, in: context)
        guard let rendered = context.makeImage() else { return nil }
        guard let crop, crop.width >= 1, crop.height >= 1 else { return rendered }
        return ImageProcessing.cropped(rendered, to: crop)
    }

    static func draw(_ annotations: [Annotation], in context: CGContext) {
        for annotation in annotations {
            draw(annotation, in: context)
        }
    }

    static func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)

        switch annotation.shape {
        case let .arrow(start, end):
            drawArrow(from: start, to: end, width: annotation.lineWidth, in: context)
        case let .line(start, end):
            context.strokeLineSegments(between: [start, end])
        case let .rectangle(rect):
            context.addPath(CGPath(roundedRect: rect, cornerWidth: min(6, rect.width / 2), cornerHeight: min(6, rect.height / 2), transform: nil))
            context.strokePath()
        case let .ellipse(rect):
            context.strokeEllipse(in: rect)
        case let .highlight(rect):
            context.setFillColor(annotation.color.cgColor.copy(alpha: 0.35) ?? annotation.color.cgColor)
            context.setBlendMode(.multiply)
            context.fill(rect)
        case let .pen(points):
            strokePolyline(points, in: context)
        case let .marker(points):
            context.setStrokeColor(annotation.color.cgColor.copy(alpha: 0.4) ?? annotation.color.cgColor)
            context.setLineWidth(annotation.lineWidth * 4)
            context.setLineCap(.square)
            context.setBlendMode(.multiply)
            strokePolyline(points, in: context)
        case let .text(origin, string):
            drawText(string, at: origin, fontSize: annotation.fontSize, color: annotation.color, in: context)
        case let .step(center, number):
            let radius = annotation.stepRadius
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let label = String(number)
            let size = textSize(label, fontSize: radius * 1.1, weight: .bold)
            drawText(label, at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), fontSize: radius * 1.1, color: annotation.color.contrastingText, weight: .bold, in: context)
        case let .blur(rect), let .pixelate(rect):
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.setLineWidth(1.5)
            context.stroke(rect)
        }
    }

    static func strokePolyline(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        if points.count == 1 {
            context.addLine(to: first)
        }
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, in context: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        let headLength = min(length * 0.6, max(14, width * 4.5))
        let headWidth = headLength * 0.8
        let base = CGPoint(x: end.x - cos(angle) * headLength * 0.85, y: end.y - sin(angle) * headLength * 0.85)
        context.strokeLineSegments(between: [start, base])
        let left = CGPoint(x: end.x - cos(angle) * headLength + sin(angle) * headWidth / 2, y: end.y - sin(angle) * headLength - cos(angle) * headWidth / 2)
        let right = CGPoint(x: end.x - cos(angle) * headLength - sin(angle) * headWidth / 2, y: end.y - sin(angle) * headLength + cos(angle) * headWidth / 2)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.fillPath()
    }

    static func attributes(fontSize: CGFloat, color: RGBAColor, weight: NSFont.Weight = .semibold) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = color.contrastingText.nsColor.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = fontSize / 10
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color.nsColor,
            .shadow: shadow,
        ]
    }

    static func textSize(_ string: String, fontSize: CGFloat, weight: NSFont.Weight = .semibold) -> CGSize {
        let size = NSAttributedString(string: string.isEmpty ? " " : string, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight)]).size()
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: RGBAColor, weight: NSFont.Weight = .semibold, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSAttributedString(string: string, attributes: attributes(fontSize: fontSize, color: color, weight: weight)).draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}
