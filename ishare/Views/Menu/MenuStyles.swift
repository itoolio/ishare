import KeyboardShortcuts
import SwiftUI

extension Color {
    static let menuAccent = Color(.displayP3, red: 0.44, green: 0.29, blue: 0.9)
}

@MainActor
func shortcutHelp(_ title: String, _ shortcut: KeyboardShortcuts.Name?) -> String {
    guard let shortcut, let keys = KeyboardShortcuts.getShortcut(for: shortcut) else { return title.localized() }
    return "\(title.localized()) (\(keys.description))"
}

struct ActionTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionTileBackground(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct ActionTileBackground<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder var content: Content
    @State private var isHovered = false
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        content
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.menuAccent : Color.primary.opacity(contrast.fillOpacity))
            )
            .overlay {
                if contrast.isHigh {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isHovered ? 0 : contrast.borderOpacity), lineWidth: 1)
                }
            }
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct MenuIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuIconButtonBody(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct MenuIconButtonBody<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder var content: Content
    @State private var isHovered = false
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        content
            .foregroundStyle(.primary)
            .background(Circle().fill(Color.primary.opacity(isHovered || isPressed ? contrast.hoverFillOpacity : contrast.iconFillOpacity)))
            .overlay { if contrast.isHigh { Circle().strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: 1) } }
            .onHover { isHovered = $0 }
    }
}
