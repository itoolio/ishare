import Defaults
import SwiftUI

enum GlassFallback: Equatable, Sendable {
    case material
    case fill(Double)
}

enum GlassRendering: Equatable, Sendable {
    case glass
    case material
    case fill(Double)
    case solid

    static func resolve(glassAvailable: Bool, reduceTransparency: Bool, fallback: GlassFallback) -> GlassRendering {
        if reduceTransparency { return .solid }
        if glassAvailable { return .glass }
        switch fallback {
        case .material: return .material
        case let .fill(opacity): return .fill(opacity)
        }
    }

    static func borderOpacity(for rendering: GlassRendering, contrast: MenuContrast) -> Double {
        if contrast.isHigh { return contrast.borderOpacity }
        switch rendering {
        case .glass, .fill: return 0
        case .material: return 0.12
        case .solid: return contrast.borderOpacity
        }
    }

    static var isGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

extension View {
    func adaptiveGlass(cornerRadius: CGFloat = 16, interactive: Bool = false, tint: Color? = nil, fallback: GlassFallback = .material) -> some View {
        modifier(AdaptiveGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive, tint: tint, fallback: fallback))
    }

    func adaptiveGlassCapsule(interactive: Bool = false, tint: Color? = nil, fallback: GlassFallback = .material) -> some View {
        modifier(AdaptiveGlassModifier(shape: Capsule(), interactive: interactive, tint: tint, fallback: fallback))
    }

    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(AdaptiveGlassButtonStyleModifier(prominent: prominent))
    }

    func adaptiveGlassBar(edge: VerticalEdge = .top) -> some View {
        modifier(AdaptiveGlassBarModifier(edge: edge))
    }
}

@MainActor
private struct ResolvedGlassContrast: DynamicProperty {
    @Environment(\.menuContrast) private var environmentContrast
    @Default(.highContrastMenu) private var highContrastMenu
    @ObservedObject private var system = SystemContrastObserver.shared

    var value: MenuContrast {
        environmentContrast.isHigh ? environmentContrast : MenuContrast.resolve(userPreference: highContrastMenu, systemIncreaseContrast: system.increaseContrast)
    }
}

private struct AdaptiveGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    let fallback: GlassFallback
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var contrast = ResolvedGlassContrast()

    init(shape: S, interactive: Bool, tint: Color?, fallback: GlassFallback) {
        self.shape = shape
        self.interactive = interactive
        self.tint = tint
        self.fallback = fallback
    }

    private var rendering: GlassRendering {
        GlassRendering.resolve(glassAvailable: GlassRendering.isGlassAvailable, reduceTransparency: reduceTransparency, fallback: fallback)
    }

    func body(content: Content) -> some View {
        let rendering = rendering
        let border = GlassRendering.borderOpacity(for: rendering, contrast: contrast.value)
        styled(content, rendering: rendering)
            .overlay {
                if border > 0 {
                    shape.strokeBorder(rendering == .material && !contrast.value.isHigh ? Color.white.opacity(border) : Color.primary.opacity(border), lineWidth: rendering == .material && !contrast.value.isHigh ? 0.5 : contrast.value.borderWidth)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private func styled(_ content: Content, rendering: GlassRendering) -> some View {
        switch rendering {
        case .glass:
            if #available(macOS 26.0, *) {
                content.glassEffect(glass(interactive: interactive, tint: tint), in: shape)
            } else {
                content.background { materialBackground }
            }
        case .material:
            content.background { materialBackground }
        case let .fill(opacity):
            content.background {
                shape.fill(Color.primary.opacity(opacity))
                    .overlay { tintOverlay }
            }
        case .solid:
            content.background {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                    .overlay { tintOverlay }
            }
        }
    }

    private var materialBackground: some View {
        shape.fill(.regularMaterial)
            .overlay { tintOverlay }
    }

    @ViewBuilder
    private var tintOverlay: some View {
        if let tint {
            shape.fill(tint.opacity(0.25))
        }
    }
}

private struct AdaptiveGlassButtonStyleModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct AdaptiveGlassBarModifier: ViewModifier {
    let edge: VerticalEdge
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var contrast = ResolvedGlassContrast()

    init(edge: VerticalEdge) {
        self.edge = edge
    }

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    Rectangle().fill(.bar)
                }
            }
            .overlay(alignment: edge == .top ? .bottom : .top) {
                if contrast.value.isHigh {
                    Rectangle()
                        .fill(Color.primary.opacity(contrast.value.borderOpacity))
                        .frame(height: 1)
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
