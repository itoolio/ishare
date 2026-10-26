import AppKit
import Defaults
import Foundation

struct AnnotationStyle: Codable, Hashable, Sendable, Defaults.Serializable {
    var color: RGBAColor?
    var lineWidth: CGFloat?
    var fontSize: CGFloat?
    var filled: Bool?
    var textBackground: Bool?
    var arrowHead: ArrowHead?
    var doubleHeaded: Bool?
    var dashed: Bool?
    var spotlightShape: SpotlightShape?
    var dimAmount: Double?
    var highlightStyle: HighlightStyle?

    init(
        color: RGBAColor? = nil, lineWidth: CGFloat? = nil, fontSize: CGFloat? = nil, filled: Bool? = nil, textBackground: Bool? = nil, arrowHead: ArrowHead? = nil,
        doubleHeaded: Bool? = nil, dashed: Bool? = nil, spotlightShape: SpotlightShape? = nil, dimAmount: Double? = nil, highlightStyle: HighlightStyle? = nil
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.filled = filled
        self.textBackground = textBackground
        self.arrowHead = arrowHead
        self.doubleHeaded = doubleHeaded
        self.dashed = dashed
        self.spotlightShape = spotlightShape
        self.dimAmount = dimAmount
        self.highlightStyle = highlightStyle
    }

    init(of annotation: Annotation) {
        let properties = annotation.styleProperties
        color = properties.contains(.color) ? annotation.color : nil
        lineWidth = properties.contains(.lineWidth) ? annotation.lineWidth : nil
        fontSize = properties.contains(.fontSize) ? annotation.fontSize : nil
        filled = properties.contains(.fill) ? annotation.filled : nil
        textBackground = properties.contains(.textBackground) ? annotation.textBackground : nil
        arrowHead = properties.contains(.arrowHead) ? annotation.arrowHead : nil
        doubleHeaded = properties.contains(.arrowHead) ? annotation.doubleHeaded : nil
        dashed = properties.contains(.dash) ? annotation.dashed : nil
        spotlightShape = properties.contains(.spotlight) ? annotation.spotlightShape : nil
        dimAmount = properties.contains(.spotlight) ? annotation.dimAmount : nil
        highlightStyle = properties.contains(.highlightStyle) ? annotation.highlightStyle : nil
    }

    var isEmpty: Bool {
        self == AnnotationStyle()
    }
}

struct AnnotationStyleProperties: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let color = AnnotationStyleProperties(rawValue: 1 << 0)
    static let lineWidth = AnnotationStyleProperties(rawValue: 1 << 1)
    static let fontSize = AnnotationStyleProperties(rawValue: 1 << 2)
    static let fill = AnnotationStyleProperties(rawValue: 1 << 3)
    static let textBackground = AnnotationStyleProperties(rawValue: 1 << 4)
    static let arrowHead = AnnotationStyleProperties(rawValue: 1 << 5)
    static let dash = AnnotationStyleProperties(rawValue: 1 << 6)
    static let spotlight = AnnotationStyleProperties(rawValue: 1 << 7)
    static let highlightStyle = AnnotationStyleProperties(rawValue: 1 << 8)
}

extension Annotation {
    var styleProperties: AnnotationStyleProperties {
        switch shape {
        case .arrow, .curvedArrow: [.color, .lineWidth, .arrowHead, .dash]
        case .line, .curvedLine: [.color, .lineWidth, .dash]
        case .rectangle, .ellipse: [.color, .lineWidth, .fill, .dash]
        case .pen, .marker: [.color, .lineWidth]
        case .magnify: [.color, .lineWidth]
        case .highlight: [.color, .highlightStyle]
        case .text: [.color, .fontSize, .textBackground]
        case .callout, .step: [.color, .fontSize]
        case .stamp: [.color]
        case .cursor: [.fontSize]
        case .spotlight: [.spotlight]
        case .blur, .pixelate, .eraser: []
        }
    }

    func applying(_ style: AnnotationStyle) -> Annotation {
        var copy = self
        let properties = styleProperties
        if properties.contains(.color), let color = style.color { copy.color = color }
        if properties.contains(.lineWidth), let lineWidth = style.lineWidth { copy.lineWidth = lineWidth }
        if properties.contains(.fontSize), let fontSize = style.fontSize { copy.fontSize = fontSize }
        if properties.contains(.fill), let filled = style.filled { copy.filled = filled }
        if properties.contains(.textBackground), let textBackground = style.textBackground { copy.textBackground = textBackground }
        if properties.contains(.arrowHead), let arrowHead = style.arrowHead { copy.arrowHead = arrowHead }
        if properties.contains(.arrowHead), let doubleHeaded = style.doubleHeaded { copy.doubleHeaded = doubleHeaded }
        if properties.contains(.dash), let dashed = style.dashed { copy.dashed = dashed }
        if properties.contains(.spotlight), let spotlightShape = style.spotlightShape { copy.spotlightShape = spotlightShape }
        if properties.contains(.spotlight), let dimAmount = style.dimAmount { copy.dimAmount = dimAmount }
        if properties.contains(.highlightStyle), let highlightStyle = style.highlightStyle { copy.highlightStyle = highlightStyle }
        return copy
    }
}

@MainActor
struct AnnotationStylePasteboard {
    static let type = NSPasteboard.PasteboardType("dev.adrian.ishare.annotation-style")
    static let shared = AnnotationStylePasteboard(pasteboard: NSPasteboard(name: NSPasteboard.Name("dev.adrian.ishare.annotation-styles")))

    let pasteboard: NSPasteboard

    func write(_ style: AnnotationStyle) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.type)
    }

    func read() -> AnnotationStyle? {
        guard let data = pasteboard.data(forType: Self.type) else { return nil }
        return try? JSONDecoder().decode(AnnotationStyle.self, from: data)
    }

    var hasStyle: Bool {
        pasteboard.availableType(from: [Self.type]) != nil
    }
}

@MainActor
final class ToolStyleStore {
    static let standard = ToolStyleStore()

    private var memory: [String: AnnotationStyle]?

    private init() {}

    init(styles: [String: AnnotationStyle]) {
        memory = styles
    }

    func style(for tool: EditorTool) -> AnnotationStyle? {
        (memory ?? Defaults[.editorToolStyles])[tool.rawValue]
    }

    func set(_ style: AnnotationStyle, for tool: EditorTool) {
        if memory != nil {
            memory?[tool.rawValue] = style
        } else {
            Defaults[.editorToolStyles][tool.rawValue] = style
        }
    }
}

extension EditorDocument {
    var styleSource: Annotation? {
        selectedAnnotation ?? selectedAnnotations.last
    }

    var canCopyStyle: Bool {
        styleSource.map { !$0.styleProperties.isEmpty } ?? false
    }

    func canPasteStyle(from pasteboard: AnnotationStylePasteboard = .shared) -> Bool {
        selectedAnnotations.contains { !$0.locked } && pasteboard.hasStyle
    }

    @discardableResult
    func copyStyle(to pasteboard: AnnotationStylePasteboard = .shared) -> Bool {
        guard let source = styleSource, !source.styleProperties.isEmpty else { return false }
        pasteboard.write(AnnotationStyle(of: source))
        return true
    }

    @discardableResult
    func pasteStyle(from pasteboard: AnnotationStylePasteboard = .shared) -> Bool {
        guard let style = pasteboard.read() else { return false }
        return applyStyle(style)
    }

    @discardableResult
    func applyStyle(_ style: AnnotationStyle) -> Bool {
        let ids = Set(selectedAnnotations.filter { !$0.locked }.map(\.id))
        guard !ids.isEmpty else { return false }
        updateAnnotations(where: { ids.contains($0.id) }) { $0 = $0.applying(style) }
        return true
    }

    func useAsDefault(_ annotation: Annotation) {
        let style = AnnotationStyle(of: annotation)
        toolStyles.set(style, for: annotation.tool)
        if annotation.tool == tool {
            adoptStyle(style)
        }
    }

    func adoptStyle(_ style: AnnotationStyle) {
        if let color = style.color { self.color = color }
        if let lineWidth = style.lineWidth { self.lineWidth = lineWidth }
        if let fontSize = style.fontSize { self.fontSize = fontSize }
        if let filled = style.filled { self.filled = filled }
        if let textBackground = style.textBackground { self.textBackground = textBackground }
        if let arrowHead = style.arrowHead { self.arrowHead = arrowHead }
        if let doubleHeaded = style.doubleHeaded { self.doubleHeaded = doubleHeaded }
        if let dashed = style.dashed { self.dashed = dashed }
        if let spotlightShape = style.spotlightShape { self.spotlightShape = spotlightShape }
        if let dimAmount = style.dimAmount { self.dimAmount = dimAmount }
        if let highlightStyle = style.highlightStyle { self.highlightStyle = highlightStyle }
    }

    func adoptDefaultStyle(for tool: EditorTool) {
        guard let style = toolStyles.style(for: tool) else { return }
        adoptStyle(style)
    }

    static func useAsDefaultTitle(for annotation: Annotation) -> String {
        String(format: "Use as Default for New %@".localized(), annotation.tool.title.localized())
    }
}
