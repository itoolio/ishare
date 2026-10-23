import AppKit
import CoreGraphics

enum EditorExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case pdf
    case svg

    var id: Self { self }

    var title: String {
        switch self {
        case .png: "Export as PNG…".localized()
        case .pdf: "Export as PDF…".localized()
        case .svg: "Export as SVG…".localized()
        }
    }
}

struct VectorExportInput {
    var base: CGImage
    var annotations: [Annotation]
    var crop: CGRect?

    var visibleAnnotations: [Annotation] {
        annotations.filter { !$0.hidden }
    }

    var imageSize: CGSize {
        CGSize(width: base.width, height: base.height)
    }

    var region: CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        guard let crop, crop.width >= 1, crop.height >= 1 else { return bounds }
        let clamped = crop.integral.intersection(bounds)
        return clamped.isNull ? bounds : clamped
    }

    var rasterizedBase: CGImage {
        AnnotationRenderer.applyingEffects(visibleAnnotations, to: base)
    }
}

enum PDFExporter {
    static func data(for input: VectorExportInput) -> Data? {
        let region = input.region
        let raster = input.rasterizedBase
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: region.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }
        context.beginPDFPage(nil)
        context.saveGState()
        context.clip(to: mediaBox)
        context.translateBy(x: 0, y: region.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -region.minX, y: -region.minY)
        context.saveGState()
        context.translateBy(x: 0, y: input.imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(raster, in: CGRect(origin: .zero, size: input.imageSize))
        context.restoreGState()
        AnnotationRenderer.draw(input.visibleAnnotations.filter { !$0.isEffect }, in: context, source: raster, canvasSize: input.imageSize)
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

enum SVGExporter {
    static let fontFamily = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif"

    static func document(for input: VectorExportInput) -> String {
        let region = input.region
        let raster = input.rasterizedBase
        let annotations = input.visibleAnnotations.filter { !$0.isEffect }
        var body: [String] = []
        if let cropped = raster.cropping(to: region), let uri = dataURI(for: cropped) {
            body.append(#"<image x="\#(number(region.minX))" y="\#(number(region.minY))" width="\#(number(region.width))" height="\#(number(region.height))" preserveAspectRatio="none" xlink:href="\#(uri)"/>"#)
        }
        let spotlights = annotations.filter(\.isSpotlight)
        if !spotlights.isEmpty {
            body.append(spotlightElement(spotlights, canvas: CGRect(origin: .zero, size: input.imageSize)))
        }
        for annotation in annotations where annotation.isMagnifier {
            body.append(contentsOf: elements(for: annotation, source: raster))
        }
        for annotation in annotations where !annotation.isSpotlight && !annotation.isMagnifier {
            body.append(contentsOf: elements(for: annotation, source: raster))
        }
        let header = #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="\#(number(region.width))" height="\#(number(region.height))" viewBox="\#(number(region.minX)) \#(number(region.minY)) \#(number(region.width)) \#(number(region.height))">"#
        return (["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", header] + body.map { "  " + $0 } + ["</svg>"]).joined(separator: "\n") + "\n"
    }

    static func number(_ value: CGFloat) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        var text = String(format: "%.2f", Double(rounded))
        while text.hasSuffix("0") {
            text.removeLast()
        }
        return text
    }

    static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }

    static func pathData(_ path: CGPath) -> String {
        var commands: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                commands.append("M\(number(points[0].x)) \(number(points[0].y))")
            case .addLineToPoint:
                commands.append("L\(number(points[0].x)) \(number(points[0].y))")
            case .addQuadCurveToPoint:
                commands.append("Q\(number(points[0].x)) \(number(points[0].y)) \(number(points[1].x)) \(number(points[1].y))")
            case .addCurveToPoint:
                commands.append("C\(number(points[0].x)) \(number(points[0].y)) \(number(points[1].x)) \(number(points[1].y)) \(number(points[2].x)) \(number(points[2].y))")
            case .closeSubpath:
                commands.append("Z")
            @unknown default:
                break
            }
        }
        return commands.joined(separator: " ")
    }

    static func color(_ color: RGBAColor) -> String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return "rgb(\(byte(color.red)),\(byte(color.green)),\(byte(color.blue)))"
    }

    private static func fill(_ paint: RGBAColor, opacity: Double = 1) -> String {
        let alpha = paint.alpha * opacity
        return #"fill="\#(color(paint))""# + (alpha < 1 ? #" fill-opacity="\#(number(alpha))""# : "")
    }

    private static func stroke(_ paint: RGBAColor, width: CGFloat, opacity: Double = 1, cap: String = "round", dash: [CGFloat]? = nil) -> String {
        let alpha = paint.alpha * opacity
        var attributes = #"fill="none" stroke="\#(color(paint))" stroke-width="\#(number(width))" stroke-linecap="\#(cap)" stroke-linejoin="round""#
        if alpha < 1 {
            attributes += #" stroke-opacity="\#(number(alpha))""#
        }
        if let dash {
            attributes += #" stroke-dasharray="\#(dash.map(number).joined(separator: " "))""#
        }
        return attributes
    }

    private static func dash(for annotation: Annotation) -> [CGFloat]? {
        annotation.dashed ? AnnotationRenderer.dashPattern(for: annotation.lineWidth) : nil
    }

    static func elements(for annotation: Annotation, source: CGImage) -> [String] {
        switch annotation.shape {
        case let .arrow(start, end):
            return arrowElements(start: start, control: nil, end: end, annotation: annotation)
        case let .curvedArrow(start, control, end):
            return arrowElements(start: start, control: control, end: end, annotation: annotation)
        case let .line(start, end):
            let cap = annotation.dashed ? "butt" : "round"
            return [#"<line x1="\#(number(start.x))" y1="\#(number(start.y))" x2="\#(number(end.x))" y2="\#(number(end.y))" \#(stroke(annotation.color, width: annotation.lineWidth, cap: cap, dash: dash(for: annotation)))/>"#]
        case let .rectangle(rect):
            let radius = min(6, rect.width / 2, rect.height / 2)
            let paint = annotation.filled
                ? fill(annotation.color)
                : stroke(annotation.color, width: annotation.lineWidth, cap: annotation.dashed ? "butt" : "round", dash: dash(for: annotation))
            return [#"<rect x="\#(number(rect.minX))" y="\#(number(rect.minY))" width="\#(number(rect.width))" height="\#(number(rect.height))" rx="\#(number(radius))" ry="\#(number(radius))" \#(paint)/>"#]
        case let .ellipse(rect):
            let paint = annotation.filled
                ? fill(annotation.color)
                : stroke(annotation.color, width: annotation.lineWidth, cap: annotation.dashed ? "butt" : "round", dash: dash(for: annotation))
            return [#"<ellipse cx="\#(number(rect.midX))" cy="\#(number(rect.midY))" rx="\#(number(rect.width / 2))" ry="\#(number(rect.height / 2))" \#(paint)/>"#]
        case let .highlight(rect):
            return [#"<rect x="\#(number(rect.minX))" y="\#(number(rect.minY))" width="\#(number(rect.width))" height="\#(number(rect.height))" \#(fill(annotation.color, opacity: 0.35)) style="mix-blend-mode:multiply"/>"#]
        case let .pen(points):
            return [#"<path d="\#(polyline(points))" \#(stroke(annotation.color, width: annotation.lineWidth))/>"#]
        case let .marker(points):
            return [#"<path d="\#(polyline(points))" \#(stroke(annotation.color, width: annotation.lineWidth * 4, opacity: 0.4, cap: "square")) style="mix-blend-mode:multiply"/>"#]
        case let .text(origin, string):
            return textElements(string, origin: origin, annotation: annotation)
        case let .callout(tail, rect, string):
            return calloutElements(tail: tail, rect: rect, text: string, annotation: annotation)
        case let .step(center, number):
            return stepElements(center: center, number: number, annotation: annotation)
        case let .magnify(rect):
            return magnifierElements(rect, source: source, annotation: annotation)
        case let .cursor(point):
            let size = AnnotationRenderer.cursorSize(for: annotation.fontSize)
            return imageElement(cursorImage(size: size), in: CGRect(origin: point, size: size)).map { [$0] } ?? []
        case let .stamp(rect, stamp):
            guard rect.width >= 1, rect.height >= 1, let image = stamp.image(size: min(rect.width, rect.height), color: annotation.color) else { return [] }
            let target = Stamp.fittedRect(for: image.size, in: rect)
            return imageElement(rasterized(image, size: target.size), in: target).map { [$0] } ?? []
        case .blur, .pixelate, .eraser, .spotlight:
            return []
        }
    }

    private static func polyline(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        let rest = points.count == 1 ? [first] : Array(points.dropFirst())
        return (["M\(number(first.x)) \(number(first.y))"] + rest.map { "L\(number($0.x)) \(number($0.y))" }).joined(separator: " ")
    }

    private static func arrowElements(start: CGPoint, control: CGPoint?, end: CGPoint, annotation: Annotation) -> [String] {
        let length = hypot(end.x - start.x, end.y - start.y)
        let headLength = ArrowGeometry.headLength(for: annotation.lineWidth, length: length)
        let retraction = annotation.arrowHead == .line ? 0 : headLength * 0.85
        let startRetraction = annotation.doubleHeaded ? retraction : 0
        let shaft: String
        if let control {
            let trimmed = ArrowGeometry.trimmed(start: start, control: control, end: end, startBy: startRetraction, endBy: retraction)
            shaft = "M\(number(trimmed.start.x)) \(number(trimmed.start.y)) Q\(number(trimmed.control.x)) \(number(trimmed.control.y)) \(number(trimmed.end.x)) \(number(trimmed.end.y))"
        } else {
            let from = ArrowGeometry.retracted(start, toward: end, by: startRetraction)
            let to = ArrowGeometry.retracted(end, toward: start, by: retraction)
            shaft = "M\(number(from.x)) \(number(from.y)) L\(number(to.x)) \(number(to.y))"
        }
        var result = [#"<path d="\#(shaft)" \#(stroke(annotation.color, width: annotation.lineWidth, cap: annotation.dashed ? "butt" : "round", dash: dash(for: annotation)))/>"#]
        result.append(arrowHead(tip: end, tail: control ?? start, length: headLength, annotation: annotation))
        if annotation.doubleHeaded {
            result.append(arrowHead(tip: start, tail: control ?? end, length: headLength, annotation: annotation))
        }
        return result
    }

    private static func arrowHead(tip: CGPoint, tail: CGPoint, length: CGFloat, annotation: Annotation) -> String {
        let (left, right) = ArrowGeometry.headPoints(tip: tip, from: tail, headLength: length)
        switch annotation.arrowHead {
        case .filled:
            return #"<path d="M\#(number(tip.x)) \#(number(tip.y)) L\#(number(left.x)) \#(number(left.y)) L\#(number(right.x)) \#(number(right.y)) Z" \#(fill(annotation.color))/>"#
        case .open:
            return #"<path d="M\#(number(tip.x)) \#(number(tip.y)) L\#(number(left.x)) \#(number(left.y)) L\#(number(right.x)) \#(number(right.y)) Z" \#(stroke(annotation.color, width: annotation.lineWidth))/>"#
        case .line:
            return #"<path d="M\#(number(left.x)) \#(number(left.y)) L\#(number(tip.x)) \#(number(tip.y)) L\#(number(right.x)) \#(number(right.y))" \#(stroke(annotation.color, width: annotation.lineWidth))/>"#
        }
    }

    static func textMetrics(fontSize: CGFloat, weight: NSFont.Weight = .semibold) -> (ascent: CGFloat, lineHeight: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return (font.ascender, lineHeight)
    }

    private static func textElement(_ string: String, origin: CGPoint, fontSize: CGFloat, color paint: RGBAColor, weight: Int = 600) -> String {
        let metrics = textMetrics(fontSize: fontSize, weight: weight >= 700 ? .bold : .semibold)
        let lines = string.components(separatedBy: "\n")
        let spans = lines.enumerated().map { index, line in
            #"<tspan x="\#(number(origin.x))" y="\#(number(origin.y + metrics.ascent + CGFloat(index) * metrics.lineHeight))">\#(escaped(line))</tspan>"#
        }.joined()
        return #"<text font-family="\#(fontFamily)" font-size="\#(number(fontSize))" font-weight="\#(weight)" \#(fill(paint)) xml:space="preserve">\#(spans)</text>"#
    }

    private static func textElements(_ string: String, origin: CGPoint, annotation: Annotation) -> [String] {
        guard annotation.textBackground else {
            return [textElement(string, origin: origin, fontSize: annotation.fontSize, color: annotation.color)]
        }
        let size = AnnotationRenderer.textSize(string, fontSize: annotation.fontSize)
        let padding = annotation.fontSize * 0.25
        let rect = CGRect(x: origin.x - padding, y: origin.y - padding / 2, width: size.width + padding * 2, height: size.height + padding)
        return [
            #"<rect x="\#(number(rect.minX))" y="\#(number(rect.minY))" width="\#(number(rect.width))" height="\#(number(rect.height))" rx="\#(number(padding))" ry="\#(number(padding))" \#(fill(annotation.color))/>"#,
            textElement(string, origin: origin, fontSize: annotation.fontSize, color: annotation.color.contrastingText),
        ]
    }

    private static func calloutElements(tail: CGPoint, rect: CGRect, text: String, annotation: Annotation) -> [String] {
        let radius = min(18, min(rect.width, rect.height) / 3)
        let bubble = AnnotationRenderer.calloutPath(tail: tail, rect: rect, radius: radius)
        var result = [#"<path d="\#(pathData(bubble))" fill-rule="nonzero" \#(fill(annotation.color))/>"#]
        if !text.isEmpty {
            let padding = annotation.fontSize * 0.4
            let size = AnnotationRenderer.textSize(text, fontSize: annotation.fontSize)
            result.append(textElement(text, origin: CGPoint(x: rect.minX + padding, y: rect.midY - size.height / 2), fontSize: annotation.fontSize, color: annotation.color.contrastingText))
        }
        return result
    }

    private static func stepElements(center: CGPoint, number value: Int, annotation: Annotation) -> [String] {
        let radius = annotation.stepRadius
        let label = String(value)
        let fontSize = radius * 1.1
        let size = AnnotationRenderer.textSize(label, fontSize: fontSize, weight: .bold)
        return [
            #"<circle cx="\#(number(center.x))" cy="\#(number(center.y))" r="\#(number(radius))" \#(fill(annotation.color))/>"#,
            textElement(label, origin: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), fontSize: fontSize, color: annotation.color.contrastingText, weight: 700),
        ]
    }

    private static func magnifierElements(_ rect: CGRect, source: CGImage, annotation: Annotation) -> [String] {
        let identifier = "lens-" + annotation.id.uuidString.lowercased()
        var result: [String] = []
        if let crop = AnnotationRenderer.magnifiedSource(for: rect, in: source), let uri = dataURI(for: crop) {
            result.append(#"<clipPath id="\#(identifier)"><ellipse cx="\#(number(rect.midX))" cy="\#(number(rect.midY))" rx="\#(number(rect.width / 2))" ry="\#(number(rect.height / 2))"/></clipPath>"#)
            result.append(#"<image x="\#(number(rect.minX))" y="\#(number(rect.minY))" width="\#(number(rect.width))" height="\#(number(rect.height))" preserveAspectRatio="none" clip-path="url(#\#(identifier))" xlink:href="\#(uri)"/>"#)
        }
        result.append(#"<ellipse cx="\#(number(rect.midX))" cy="\#(number(rect.midY))" rx="\#(number(rect.width / 2))" ry="\#(number(rect.height / 2))" \#(stroke(annotation.color, width: max(3, annotation.lineWidth)))/>"#)
        return result
    }

    private static func spotlightElement(_ spotlights: [Annotation], canvas: CGRect) -> String {
        let dim = min(1, max(0, spotlights.map(\.dimAmount).max() ?? Annotation.defaultDimAmount))
        let holes = spotlights.compactMap(AnnotationRenderer.spotlightPath).map(pathData).joined(separator: " ")
        let outline = "M\(number(canvas.minX)) \(number(canvas.minY)) H\(number(canvas.maxX)) V\(number(canvas.maxY)) H\(number(canvas.minX)) Z"
        return #"<path d="\#(outline) \#(holes)" fill-rule="evenodd" fill="rgb(0,0,0)" fill-opacity="\#(number(dim))"/>"#
    }

    private static func imageElement(_ image: CGImage?, in rect: CGRect) -> String? {
        guard let image, let uri = dataURI(for: image) else { return nil }
        return #"<image x="\#(number(rect.minX))" y="\#(number(rect.minY))" width="\#(number(rect.width))" height="\#(number(rect.height))" preserveAspectRatio="none" xlink:href="\#(uri)"/>"#
    }

    static func dataURI(for image: CGImage) -> String? {
        guard let data = try? ImageEncoder.data(for: image, as: .PNG) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    private static func rasterized(_ image: NSImage, size: CGSize) -> CGImage? {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func cursorImage(size: CGSize) -> CGImage? {
        rasterized(NSCursor.arrow.image, size: size)
    }
}
