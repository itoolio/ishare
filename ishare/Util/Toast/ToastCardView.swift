import Defaults
import SwiftUI

struct ToastCardView: View {
    static let width: CGFloat = 384

    @ObservedObject var model: ToastModel

    var body: some View {
        ToastCardContent(model: model)
            .menuAppearance(appliesToWindow: false)
    }
}

struct ToastCardContent: View {
    @ObservedObject var model: ToastModel
    @Default(.saveToDisk) var saveToDisk
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Group {
            if let session = model.annotation {
                annotating(session)
            } else {
                card
            }
        }
        .adaptiveGlass(cornerRadius: 18)
        .opacity(model.isDragging ? 0.3 : 1)
        .onHover { hovering in
            if hovering {
                model.isDragging = false
            }
            model.isHovering = hovering
            model.onHoverChange(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast.card")
    }

    private func annotating(_ session: QuickAnnotateSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.tip.crop.circle")
                    .accessibilityHidden(true)
                    .foregroundStyle(Color.menuAccent)
                Text(model.fileName)
                    .font(.system(size: 13, weight: Font.Weight.semibold.emphasized(contrast)))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 18)
            }
            QuickAnnotateCanvas(session: session)
                .frame(maxWidth: .infinity)
            QuickAnnotateToolbar(session: session) {
                model.cancelAnnotating()
            } onDone: {
                Task { @MainActor in
                    await model.finishAnnotating()
                }
            }
        }
        .padding(12)
        .frame(width: ToastCardView.width, alignment: .leading)
        .accessibilityIdentifier("toast.annotate")
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.message?.title ?? model.fileName)
                        .font(.system(size: 13, weight: Font.Weight.semibold.emphasized(contrast)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 18)
                }
                detail
                replacementPrompt
                if model.fileURL != nil {
                    actions
                }
            }
        }
        .padding(12)
        .frame(width: ToastCardView.width, alignment: .leading)
        .overlay(alignment: .topTrailing) { dismissButton }
    }

    @ViewBuilder
    private var leading: some View {
        if let message = model.message {
            Image(systemName: message.symbol)
                .accessibilityHidden(true)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(message.tint)
                .frame(width: 40, height: 40)
        } else {
            thumbnail
        }
    }

    private var dismissButton: some View {
        Button {
            model.onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(model.isHovering ? contrast.hoverFillOpacity : contrast.iconFillOpacity)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .help("Dismiss".localized())
        .accessibilityLabel("Dismiss".localized())
        .accessibilityIdentifier("toast.dismiss")
    }
}
