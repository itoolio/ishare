import SwiftUI

struct MenuFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            FooterButton(symbol: "pencil.and.scribble", title: "Edit Image…") {
                MenuActions.editImage()
            }
            .favoriteContextMenu(MenuFavoriteCommandID.footer(0))
            .menuFocusRing(.footer(0))
            .accessibilityIdentifier("menu.editImage")
            FooterButton(symbol: "doc.on.clipboard", title: "Upload Clipboard") {
                MenuActions.uploadClipboard()
            }
            .favoriteContextMenu(MenuFavoriteCommandID.footer(1))
            .menuFocusRing(.footer(1))
            .accessibilityIdentifier("menu.uploadClipboard")
        }
    }

    static func activate(_ index: Int) {
        if index == 0 {
            MenuActions.editImage()
        } else {
            MenuActions.uploadClipboard()
        }
    }
}

struct FooterButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @Environment(\.menuMetrics) private var metrics
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Label(title.localized(), systemImage: symbol)
                .font(.system(size: 12, weight: Font.Weight.medium.emphasized(contrast)))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.footerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActionTileStyle())
    }
}
