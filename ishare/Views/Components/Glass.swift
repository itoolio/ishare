import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat = 16, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(glass(interactive: interactive, tint: tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.25))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    }
            }
        }
    }

    @ViewBuilder
    func adaptiveGlassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(glass(interactive: interactive, tint: tint), in: .capsule)
        } else {
            background {
                Capsule().fill(.regularMaterial)
                    .overlay {
                        if let tint {
                            Capsule().fill(tint.opacity(0.25))
                        }
                    }
            }
        }
    }

    @ViewBuilder
    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

@available(macOS 26.0, *)
private func glass(interactive: Bool, tint: Color?) -> Glass {
    var glass = Glass.regular
    if let tint {
        glass = glass.tint(tint)
    }
    return interactive ? glass.interactive() : glass
}

struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
