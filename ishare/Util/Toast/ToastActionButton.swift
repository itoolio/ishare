import SwiftUI

struct ToastActionLabel: View {
    let symbol: String
    let title: String
    var iconOnly = false
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Group {
            if iconOnly {
                Image(systemName: symbol)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(contrast.fillOpacity)))
                    .overlay { if contrast.isHigh { Circle().strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: 1) } }
                    .contentShape(Circle())
            } else {
                Label(title.localized(), systemImage: symbol)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.primary.opacity(contrast.fillOpacity)))
                    .overlay { if contrast.isHigh { Capsule().strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: 1) } }
                    .contentShape(Capsule())
            }
        }
        .font(.system(size: 11, weight: Font.Weight.medium.emphasized(contrast)))
        .fixedSize()
    }
}

struct ToastActionButton: View {
    let symbol: String
    let title: String
    var iconOnly = false
    let identifier: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ToastActionLabel(symbol: symbol, title: title, iconOnly: iconOnly)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel(title.localized())
        .accessibilityIdentifier(identifier)
    }
}
