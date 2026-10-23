import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuSectionTitle: View {
    let title: String
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Text(title.localized())
            .font(.system(size: 11, weight: Font.Weight.semibold.emphasized(contrast)))
            .foregroundStyle(contrast.isHigh ? AnyShapeStyle(Color.primary.opacity(contrast.secondaryOpacity)) : AnyShapeStyle(.secondary))
            .accessibilityAddTraits(.isHeader)
    }
}

struct MenuSecondaryText: View {
    let text: String
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: Font.Weight.regular.emphasized(contrast)))
            .foregroundStyle(contrast.isHigh ? AnyShapeStyle(Color.primary.opacity(contrast.secondaryOpacity)) : AnyShapeStyle(.secondary))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ActionTileLabel: View {
    let symbol: String
    let title: String
    @Environment(\.menuMetrics) private var metrics
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        VStack(spacing: metrics.tileSpacing) {
            Image(systemName: symbol)
                .font(.system(size: metrics.tileSymbolSize, weight: Font.Weight.medium.emphasized(contrast)))
                .frame(height: metrics.tileSymbolSize + 3)
                .accessibilityHidden(true)
            Text(title.localized())
                .font(.system(size: 11, weight: Font.Weight.medium.emphasized(contrast)))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.tileHeight)
        .contentShape(Rectangle())
    }
}

struct ActionTile: View {
    let symbol: String
    let title: String
    var shortcut: KeyboardShortcuts.Name?
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionTileLabel(symbol: symbol, title: title)
        }
        .buttonStyle(ActionTileStyle())
        .help(shortcutHelp(title, shortcut))
        .accessibilityIdentifier(identifier)
    }
}

struct WideActionButton: View {
    let symbol: String
    let title: String
    var help: String?
    var shortcut: KeyboardShortcuts.Name?
    var identifier: String = ""
    let action: () -> Void
    @Environment(\.menuMetrics) private var metrics
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: Font.Weight.medium.emphasized(contrast)))
                    .accessibilityHidden(true)
                Text(title.localized())
                    .font(.system(size: 12, weight: Font.Weight.medium.emphasized(contrast)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.wideHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionTileStyle())
        .help(shortcutHelp(help ?? title, shortcut))
        .accessibilityIdentifier(identifier)
    }
}

struct ToggleChip: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: Font.Weight.semibold.emphasized(contrast)))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isOn ? Color.menuAccent : Color.primary.opacity(contrast.fillOpacity)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(isOn ? 0 : contrast.borderOpacity), lineWidth: contrast.borderWidth))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel(title.localized())
        .accessibilityToggleState(isOn)
    }
}

struct ShareChip: View {
    let image: NSImage?
    let title: String
    @Binding var isOn: Bool
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(nsImage: image ?? NSImage())
                .resizable()
                .frame(width: 18, height: 18)
                .saturation(isOn ? 1 : 0)
                .opacity(isOn ? 1 : contrast.dimmedOpacity)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isOn ? Color.menuAccent.opacity(0.35) : Color.clear))
                .overlay(Circle().strokeBorder(isOn ? Color.menuAccent : Color.primary.opacity(contrast.borderOpacity), lineWidth: isOn ? 1.5 : contrast.borderWidth))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel(title.localized())
        .accessibilityToggleState(isOn)
    }
}
