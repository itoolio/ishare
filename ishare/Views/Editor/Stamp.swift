import AppKit
import CoreGraphics

enum Stamp: Hashable, Sendable {
    case emoji(String)
    case symbol(String)

    static let commonEmoji = [
        "😀", "😂", "😍", "😎", "🤔", "😮", "😢", "😡",
        "👍", "👎", "👏", "🙏", "👀", "💡", "🔥", "✨",
        "🎉", "💯", "❤️", "⭐️", "✅", "❌", "⚠️", "🚀",
    ]

    static let symbols = [
        "checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill",
        "questionmark.circle.fill", "star.fill", "heart.fill",
    ]

    static let `default` = Stamp.symbol("checkmark.circle.fill")

    static func firstEmoji(in text: String) -> String? {
        text.reversed().first { character in
            character.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0xFF) }
        }.map(String.init)
    }

    var accessibilityName: String {
        switch self {
        case let .emoji(value): value
        case let .symbol(name): name
        }
    }

    func image(size: CGFloat, color: RGBAColor) -> NSImage? {
        switch self {
        case let .emoji(value):
            let font = NSFont(name: "Apple Color Emoji", size: size * 0.8) ?? NSFont.systemFont(ofSize: size * 0.8)
            let string = NSAttributedString(string: value, attributes: [.font: font])
            let textSize = string.size()
            guard textSize.width > 0, textSize.height > 0 else { return nil }
            return NSImage(size: textSize, flipped: false) { rect in
                string.draw(at: CGPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
                return true
            }
        case let .symbol(name):
            let palette: [NSColor] = name.contains(".circle.fill") || name.contains(".triangle.fill")
                ? [color.contrastingText.nsColor, color.nsColor]
                : [color.nsColor]
            let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: palette))
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        }
    }

    static func fittedRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
