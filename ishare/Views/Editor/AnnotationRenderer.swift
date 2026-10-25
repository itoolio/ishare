import AppKit
import CoreGraphics

enum AnnotationRenderer {
    static let magnification: CGFloat = 2

    static func blurRadius(for rect: CGRect) -> CGFloat {
        max(10, min(rect.width, rect.height) / 8)
    }

    static func pixelBlockSize(for rect: CGRect) -> CGFloat {
        max(8, min(rect.width, rect.height) / 14)
    }

    static func applyingEffect(_ annotation: Annotation, to image: CGImage, parameterScale: CGFloat = 1, region: CGRect? = nil) -> CGImage {
        guard let frame = annotation.rotatedFrame else {
            return applyingAxisAlignedEffect(annotation, to: image, parameterScale: parameterScale, region: region)
        }
        let bounds = frame.boundingBox
        let target = region ?? bounds
        let effected = applyingAxisAlignedEffect(annotation, to: image, parameterScale: parameterScale, region: target)
        let scaleX = target.width / max(bounds.width, .leastNonzeroMagnitude)
        let scaleY = target.height / max(bounds.height, .leastNonzeroMagnitude)
        let polygon = frame.corners.map { CGPoint(x: target.minX + ($0.x - bounds.minX) * scaleX, y: target.minY + ($0.y - bounds.minY) * scaleY) }
        return ImageProcessing.composite(effected, over: image, inside: polygon)
    }

    static func applyingAxisAlignedEffect(_ annotation: Annotation, to image: CGImage, parameterScale: CGFloat, region: CGRect?) -> CGImage {
        switch annotation.shape {
        case let .blur(rect):
            ImageProcessing.blur(image, region: region ?? rect, radius: max(1, blurRadius(for: rect) * parameterScale))
        case let .pixelate(rect):
            ImageProcessing.pixelate(image, region: region ?? rect, blockSize: max(1, pixelBlockSize(for: rect) * parameterScale))
        case let .eraser(rect):
            ImageProcessing.erase(image, region: region ?? rect)
        default:
            image
        }
    }

    static func applyingEffects(_ annotations: [Annotation], to base: CGImage) -> CGImage {
        annotations.filter { $0.isEffect && !$0.hidden }.reduce(base) { image, annotation in
            applyingEffect(annotation, to: image)
        }
    }

    static func render(base: CGImage, annotations allAnnotations: [Annotation], crop: CGRect?) -> CGImage? {
        let annotations = allAnnotations.filter { !$0.hidden }
        let effected = applyingEffects(annotations, to: base)
        let width = effected.width
        let height = effected.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.draw(effected, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(annotations.filter { !$0.isEffect }, in: context, source: effected, canvasSize: CGSize(width: width, height: height))
        guard let rendered = context.makeImage() else { return nil }
        guard let crop, crop.width >= 1, crop.height >= 1 else { return rendered }
        return ImageProcessing.cropped(rendered, to: crop)
    }

    static func draw(_ annotations: [Annotation], in context: CGContext, source: CGImage?, canvasSize: CGSize) {
        let spotlights = annotations.filter(\.isSpotlight)
        if !spotlights.isEmpty {
            drawSpotlights(spotlights, canvasSize: canvasSize, in: context)
        }
        for annotation in annotations where annotation.isMagnifier {
            draw(annotation, in: context, source: source)
        }
        for annotation in annotations where !annotation.isSpotlight && !annotation.isMagnifier {
            draw(annotation, in: context, source: source)
        }
    }

    static func magnifiedSource(for rect: CGRect, in source: CGImage) -> CGImage? {
        let sourceRect = CGRect(
            x: rect.midX - rect.width / (2 * magnification), y: rect.midY - rect.height / (2 * magnification),
            width: rect.width / magnification, height: rect.height / magnification
        ).integral
        return source.cropping(to: sourceRect.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height)))
    }

    static func spotlightPath(_ spotlight: Annotation) -> CGPath? {
        guard case let .spotlight(rect) = spotlight.shape else { return nil }
        var transform = spotlight.rotatedFrame?.transform ?? .identity
        switch spotlight.spotlightShape {
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: &transform)
        case .rectangle:
            let radius = min(8, rect.width / 2, rect.height / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: &transform)
        }
    }

    static func drawSpotlights(_ spotlights: [Annotation], canvasSize: CGSize, in context: CGContext) {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let dim = spotlights.map(\.dimAmount).max() ?? Annotation.defaultDimAmount
        context.saveGState()
        context.beginTransparencyLayer(in: canvas, auxiliaryInfo: nil)
        context.setFillColor(CGColor(gray: 0, alpha: min(1, max(0, dim))))
        context.fill(canvas)
        context.setBlendMode(.clear)
        for path in spotlights.compactMap(spotlightPath) {
            context.addPath(path)
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    static func draw(_ annotation: Annotation, in context: CGContext, source: CGImage? = nil) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)
        if let frame = annotation.rotatedFrame {
            context.concatenate(frame.transform)
        }

        switch annotation.shape {
        case let .arrow(start, end):
            drawArrow(from: start, control: nil, to: end, annotation: annotation, in: context)
        case let .curvedArrow(start, control, end):
            drawArrow(from: start, control: control, to: end, annotation: annotation, in: context)
        case let .line(start, end):
            applyDash(for: annotation, in: context)
            context.strokeLineSegments(between: [start, end])
        case let .curvedLine(start, control, end):
            applyDash(for: annotation, in: context)
            context.beginPath()
            context.move(to: start)
            context.addQuadCurve(to: end, control: control)
            context.strokePath()
        case let .stamp(rect, stamp):
            drawStamp(stamp, in: rect, color: annotation.color, context: context)
        case let .rectangle(rect):
            let path = CGPath(roundedRect: rect, cornerWidth: min(6, rect.width / 2), cornerHeight: min(6, rect.height / 2), transform: nil)
            context.addPath(path)
            if annotation.filled {
                context.fillPath()
            } else {
                applyDash(for: annotation, in: context)
                context.strokePath()
            }
        case let .ellipse(rect):
            if annotation.filled {
                context.fillEllipse(in: rect)
            } else {
                applyDash(for: annotation, in: context)
                context.strokeEllipse(in: rect)
            }
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
            if annotation.textBackground {
                let size = textSize(string, fontSize: annotation.fontSize)
                let padding = annotation.fontSize * 0.25
                let rect = CGRect(x: origin.x - padding, y: origin.y - padding / 2, width: size.width + padding * 2, height: size.height + padding)
                context.setFillColor(annotation.color.cgColor)
                context.addPath(CGPath(roundedRect: rect, cornerWidth: padding, cornerHeight: padding, transform: nil))
                context.fillPath()
                drawText(string, at: origin, fontSize: annotation.fontSize, color: annotation.color.contrastingText, shadow: false, in: context)
            } else {
                drawText(string, at: origin, fontSize: annotation.fontSize, color: annotation.color, in: context)
            }
        case let .callout(tail, rect, string):
            drawCallout(tail: annotation.localPoint(tail), rect: rect, text: string, annotation: annotation, in: context)
        case let .step(center, number):
            let radius = annotation.stepRadius
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let label = String(number)
            let size = textSize(label, fontSize: radius * 1.1, weight: .bold)
            drawText(
                label, at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), fontSize: radius * 1.1, color: annotation.color.contrastingText, weight: .bold,
                shadow: false, in: context)
        case let .magnify(rect):
            drawMagnifier(rect, source: source, annotation: annotation, in: context)
        case let .cursor(point):
            drawCursor(at: point, fontSize: annotation.fontSize, in: context)
        case let .blur(rect), let .pixelate(rect), let .eraser(rect), let .spotlight(rect):
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.setLineWidth(1.5)
            context.stroke(rect)
        }
    }

    static func calloutPath(tail: CGPoint, rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard !rect.contains(tail) else {
            path.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            return path
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = atan2(tail.y - center.y, tail.x - center.x)
        let baseWidth = max(12, min(rect.width, rect.height) * 0.25)
        let perpendicular = CGPoint(x: -sin(angle) * baseWidth / 2, y: cos(angle) * baseWidth / 2)
        let inset = CGPoint(x: center.x + cos(angle) * min(rect.width, rect.height) * 0.25, y: center.y + sin(angle) * min(rect.width, rect.height) * 0.25)
        path.move(to: CGPoint(x: inset.x + perpendicular.x, y: inset.y + perpendicular.y))
        path.addLine(to: tail)
        path.addLine(to: CGPoint(x: inset.x - perpendicular.x, y: inset.y - perpendicular.y))
        path.closeSubpath()
        path.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        return path
    }

    static func drawCallout(tail: CGPoint, rect: CGRect, text: String, annotation: Annotation, in context: CGContext) {
        let radius = min(18, min(rect.width, rect.height) / 3)
        context.setFillColor(annotation.color.cgColor)
        context.addPath(calloutPath(tail: tail, rect: rect, radius: radius))
        context.fillPath(using: .winding)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        guard !text.isEmpty else { return }
        let padding = annotation.fontSize * 0.4
        let size = textSize(text, fontSize: annotation.fontSize)
        let origin = CGPoint(x: rect.minX + padding, y: rect.midY - size.height / 2)
        drawText(text, at: origin, fontSize: annotation.fontSize, color: annotation.color.contrastingText, shadow: false, in: context)
    }

    static func calloutTextOrigin(for rect: CGRect, fontSize: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + fontSize * 0.4, y: rect.midY - textSize("Ag", fontSize: fontSize).height / 2)
    }

    static func drawMagnifier(_ rect: CGRect, source: CGImage?, annotation: Annotation, in context: CGContext) {
        defer {
            context.setLineWidth(max(3, annotation.lineWidth))
            context.strokeEllipse(in: rect)
        }
        guard let source, let crop = magnifiedSource(for: rect, in: source) else { return }
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    static func cursorSize(for fontSize: CGFloat) -> CGSize {
        let height = max(24, fontSize * 1.2)
        let image = NSCursor.arrow.image
        let ratio = image.size.width / max(1, image.size.height)
        return CGSize(width: height * ratio, height: height)
    }

    static func drawCursor(at point: CGPoint, fontSize: CGFloat, in context: CGContext) {
        let image = NSCursor.arrow.image
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cursor = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        let size = cursorSize(for: fontSize)
        context.saveGState()
        context.translateBy(x: point.x, y: point.y + size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cursor, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
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

    static func dashPattern(for lineWidth: CGFloat) -> [CGFloat] {
        [max(2, lineWidth * 2.2), max(3, lineWidth * 2)]
    }

    static func applyDash(for annotation: Annotation, in context: CGContext) {
        guard annotation.dashed else { return }
        context.setLineCap(.butt)
        context.setLineDash(phase: 0, lengths: dashPattern(for: annotation.lineWidth))
    }

    static func drawArrow(from start: CGPoint, control: CGPoint?, to end: CGPoint, annotation: Annotation, in context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        let headLength = ArrowGeometry.headLength(for: annotation.lineWidth, length: length)
        let angles = ArrowGeometry.headAngles(start: start, control: control, end: end)
        let retraction = annotation.arrowHead == .line ? 0 : headLength * 0.85
        let startRetraction = annotation.doubleHeaded ? retraction : 0
        context.saveGState()
        applyDash(for: annotation, in: context)
        context.beginPath()
        if let control {
            let trimmed = ArrowGeometry.trimmed(start: start, control: control, end: end, startBy: startRetraction, endBy: retraction)
            context.move(to: trimmed.start)
            context.addQuadCurve(to: trimmed.end, control: trimmed.control)
        } else {
            context.move(to: ArrowGeometry.retracted(start, toward: end, by: startRetraction))
            context.addLine(to: ArrowGeometry.retracted(end, toward: start, by: retraction))
        }
        context.strokePath()
        context.restoreGState()
        drawArrowHead(tip: end, angle: angles.end, length: headLength, annotation: annotation, in: context)
        if annotation.doubleHeaded {
            drawArrowHead(tip: start, angle: angles.start, length: headLength, annotation: annotation, in: context)
        }
    }

    static func drawArrowHead(tip: CGPoint, angle: CGFloat, length: CGFloat, annotation: Annotation, in context: CGContext) {
        let (left, right) = ArrowGeometry.headPoints(tip: tip, angle: angle, headLength: length)
        context.beginPath()
        switch annotation.arrowHead {
        case .filled:
            context.move(to: tip)
            context.addLine(to: left)
            context.addLine(to: right)
            context.closePath()
            context.fillPath()
        case .open:
            context.move(to: tip)
            context.addLine(to: left)
            context.addLine(to: right)
            context.closePath()
            context.strokePath()
        case .line:
            context.move(to: left)
            context.addLine(to: tip)
            context.addLine(to: right)
            context.strokePath()
        }
    }

    static func drawStamp(_ stamp: Stamp, in rect: CGRect, color: RGBAColor, context: CGContext) {
        guard rect.width >= 1, rect.height >= 1, let image = stamp.image(size: min(rect.width, rect.height), color: color) else { return }
        let target = Stamp.fittedRect(for: image.size, in: rect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    static func attributes(fontSize: CGFloat, color: RGBAColor, weight: NSFont.Weight = .semibold, shadow: Bool = true) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color.nsColor,
        ]
        if shadow {
            let textShadow = NSShadow()
            textShadow.shadowColor = color.contrastingText.nsColor.withAlphaComponent(0.35)
            textShadow.shadowBlurRadius = fontSize / 10
            attributes[.shadow] = textShadow
        }
        return attributes
    }

    static func textSize(_ string: String, fontSize: CGFloat, weight: NSFont.Weight = .semibold) -> CGSize {
        let size = NSAttributedString(string: string.isEmpty ? " " : string, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight)]).size()
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: RGBAColor, weight: NSFont.Weight = .semibold, shadow: Bool = true, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSAttributedString(string: string, attributes: attributes(fontSize: fontSize, color: color, weight: weight, shadow: shadow)).draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}
