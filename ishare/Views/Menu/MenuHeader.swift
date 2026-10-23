import Defaults
import SettingsAccess
import SwiftUI

struct MenuHeader: View {
    let isPreview: Bool
    let destinationAnchor: ViewAnchor
    let moreAnchor: ViewAnchor
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @Default(.uploadType) private var uploadType
    @Default(.activeCustomUploader) private var activeCustomUploader
    @Default(.uploadDestination) private var uploadDestination

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? AppIcon)
                .resizable()
                .frame(width: 24, height: 24)
            Text("ishare")
                .font(.system(size: 14, weight: .semibold))
                .fixedSize()
            Spacer(minLength: 4)
            destinationPicker
            if MenuActions.showsDonate {
                donateButton
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            } preAction: {
                app.menuActions.dismiss()
                NSApp.activate(ignoringOtherApps: true)
            } postAction: {}
                .buttonStyle(MenuIconButtonStyle())
                .help("Settings".localized())
                .keyboardShortcut(",")
                .menuFocusRing(.settings, shape: .circle)
                .accessibilityIdentifier("menu.settings")
            moreMenu
        }
    }

    private var destinationTitle: String {
        _ = (uploadType, activeCustomUploader)
        return UploadDestinationSwitcher.title(for: uploadDestination)
    }

    private var destinationPicker: some View {
        Button {
            guard !isPreview else { return }
            app.menuActions.showDestinationMenu(from: destinationAnchor)
        } label: {
            DestinationPillLabel(title: destinationTitle)
        }
        .buttonStyle(.plain)
        .anchored(to: destinationAnchor)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .help(String(format: "%@: %@", "Upload Destination".localized(), destinationTitle))
        .menuFocusRing(.destination, shape: .roundedRectangle(13))
        .accessibilityLabel("Upload Destination".localized())
        .accessibilityValue(destinationTitle)
        .accessibilityIdentifier("menu.destination")
    }

    private var donateButton: some View {
        Button {
            guard !isPreview else { return }
            app.menuActions.openDonation()
        } label: {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.menuAccent)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuIconButtonStyle())
        .fixedSize()
        .help("Donate".localized())
        .menuFocusRing(.donate, shape: .circle)
        .accessibilityLabel("Donate".localized())
        .accessibilityIdentifier("menu.donate")
    }

    private var moreMenu: some View {
        Button {
            guard !isPreview else { return }
            app.menuActions.showOverflowMenu(from: moreAnchor, openWindow: openWindow)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuIconButtonStyle())
        .anchored(to: moreAnchor)
        .fixedSize()
        .help("More".localized())
        .menuFocusRing(.more, shape: .circle)
        .accessibilityLabel("More".localized())
        .accessibilityIdentifier("menu.more")
    }
}

private struct DestinationPillLabel: View {
    let title: String
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: Font.Weight.medium.emphasized(contrast)))
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(Color.primary.opacity(contrast.isHigh ? 0.18 : 0.09)))
        .overlay { if contrast.isHigh { Capsule().strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: 1) } }
        .contentShape(Capsule())
    }
}
