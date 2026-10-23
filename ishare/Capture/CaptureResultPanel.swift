import AppKit
import SwiftUI

@MainActor
final class CaptureResultPanel {
    private let panel: HUDPanel

    init(size: CGSize, content: some View) {
        let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        let frame = CGRect(origin: Self.origin(for: size, on: NSScreen.underMouse ?? NSScreen.main), size: size)
        panel = HUDPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
    }

    var window: NSWindow { panel }

    func show() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        panel.orderOut(nil)
    }

    nonisolated static func origin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.minY + (visibleFrame.height - size.height) * 0.6
        return CGPoint(
            x: min(max(visibleFrame.minX + 8, x), max(visibleFrame.minX + 8, visibleFrame.maxX - size.width - 8)),
            y: min(max(visibleFrame.minY + 8, y), max(visibleFrame.minY + 8, visibleFrame.maxY - size.height - 8))
        )
    }

    private static func origin(for size: CGSize, on screen: NSScreen?) -> CGPoint {
        origin(for: size, in: screen?.visibleFrame ?? CGRect(origin: .zero, size: size))
    }
}

struct CaptureResultHeader: View {
    let symbol: String
    let title: String
    let subtitle: String?
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Close".localized())
            .accessibilityLabel("Close".localized())
        }
    }
}

struct CaptureResultTextBox: View {
    let title: String
    let text: String
    var placeholder: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Group {
                    if text.isEmpty, let placeholder {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(text)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }
}
