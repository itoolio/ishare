import Defaults
import SwiftUI

struct MenuFooter: View {
    @EnvironmentObject private var app: AppModel
    @Default(.captureShelfMode) private var shelfMode

    var body: some View {
        HStack(spacing: 8) {
            FooterButton(symbol: "pencil.and.scribble", title: "Edit Image…") {
                app.menuActions.editImage()
            }
            .favoriteContextMenu(MenuFavoriteCommandID.footer(0))
            .menuFocusRing(.footer(0))
            .accessibilityIdentifier("menu.editImage")
            FooterButton(symbol: "doc.on.clipboard", title: "Upload Clipboard") {
                app.menuActions.uploadClipboard()
            }
            .favoriteContextMenu(MenuFavoriteCommandID.footer(1))
            .menuFocusRing(.footer(1))
            .accessibilityIdentifier("menu.uploadClipboard")
            if shelfMode != .off {
                ShelfFooterButton {
                    app.menuActions.dismiss()
                    CaptureShelf.shared.toggle()
                }
            }
        }
    }

    static func activate(_ index: Int, using actions: MenuActions) {
        if index == 0 {
            actions.editImage()
        } else {
            actions.uploadClipboard()
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

struct ShelfFooterButton: View {
    let action: () -> Void
    @Environment(\.menuMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .medium))
                .frame(width: metrics.footerHeight, height: metrics.footerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActionTileStyle())
        .helpAndAccessibilityLabel("Capture Shelf".localized())
        .accessibilityIdentifier("menu.shelf")
    }
}
