import AppKit
import SwiftUI

struct MenuCaptureSection: View {
    var body: some View {
        HStack(spacing: 8) {
            ActionTile(symbol: "rectangle.dashed", title: "Region", shortcut: .captureRegion, identifier: "menu.capture.region") {
                MenuActions.triggerCapture(0)
            }
            .favoriteContextMenu(MenuFavoriteCommandID.capture(0))
            .menuFocusRing(.capture(0))
            ActionTile(symbol: "macwindow", title: "Window", shortcut: .captureWindow, identifier: "menu.capture.window") {
                MenuActions.triggerCapture(1)
            }
            .favoriteContextMenu(MenuFavoriteCommandID.capture(1))
            .menuFocusRing(.capture(1))
            if NSScreen.screens.count > 1 {
                screenPicker
            } else {
                ActionTile(symbol: "display", title: "Screen", shortcut: .captureScreen, identifier: "menu.capture.screen") {
                    MenuActions.triggerCapture(2)
                }
                .favoriteContextMenu(MenuFavoriteCommandID.capture(2))
                .menuFocusRing(.capture(2))
            }
            ActionTile(symbol: "arrow.up.and.down.text.horizontal", title: "Scrolling", shortcut: .captureScrolling, identifier: "menu.capture.scrolling") {
                MenuActions.triggerCapture(3)
            }
            .favoriteContextMenu(MenuFavoriteCommandID.capture(3))
            .menuFocusRing(.capture(3))
        }
    }

    private var screenPicker: some View {
        Menu {
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                Button(screen.localizedName) {
                    MenuActions.run { await CaptureSession.captureImage(.SCREEN, display: index + 1) }
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
