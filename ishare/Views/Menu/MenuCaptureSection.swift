import AppKit
import SwiftUI

struct MenuCaptureSection: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ActionTile(symbol: "rectangle.dashed", title: "Region", shortcut: .captureRegion, identifier: "menu.capture.region") {
                app.menuActions.triggerCapture(0)
            }
            .favoriteContextMenu(MenuFavoriteCommandID.capture(0))
            .menuFocusRing(.capture(0))
            ActionTile(symbol: "macwindow", title: "Window", shortcut: .captureWindow, identifier: "menu.capture.window") {
                app.menuActions.triggerCapture(1)
            }
            .favoriteContextMenu(MenuFavoriteCommandID.capture(1))
            .menuFocusRing(.capture(1))
            if NSScreen.screens.count > 1 {
                screenPicker
            } else {
                ActionTile(symbol: "display", title: "Screen", shortcut: .captureScreen, identifier: "menu.capture.screen") {
                    app.menuActions.triggerCapture(2)
                }
                .favoriteContextMenu(MenuFavoriteCommandID.capture(2))
                .menuFocusRing(.capture(2))
            }
            ActionTile(symbol: "arrow.up.and.down.text.horizontal", title: "Scrolling", shortcut: .captureScrolling, identifier: "menu.capture.scrolling") {
                app.menuActions.triggerCapture(3)
            }
            .favoriteContextMenu(MenuFavoriteCommandID.capture(3))
            .menuFocusRing(.capture(3))
        }
    }

    private var screenPicker: some View {
        Menu {
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                Button(screen.localizedName) {
                    app.menuActions.run { await CaptureSession.captureImage(.SCREEN, display: index + 1) }
                }
            }
        } label: {
            ActionTileLabel(symbol: "display.2", title: "Screen")
        }
        .menuStyle(.button)
        .buttonStyle(ActionTileStyle())
        .menuIndicator(.hidden)
        .favoriteContextMenu(MenuFavoriteCommandID.capture(2))
        .menuFocusRing(.capture(2))
        .accessibilityIdentifier("menu.capture.screen")
    }
}
