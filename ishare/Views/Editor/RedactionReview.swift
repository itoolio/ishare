import Defaults
import SwiftUI

extension Annotation {
    var isRedaction: Bool {
        switch shape {
        case .blur, .pixelate: true
        default: false
        }
    }
}

extension EditorDocument {
    var redactions: [Annotation] {
        annotations.filter { $0.isRedaction && !$0.hidden }
    }

    static func reviewRect(for rect: CGRect, in bounds: CGRect) -> CGRect {
        let margin = max(24, max(rect.width, rect.height) * 0.4)
        return rect.insetBy(dx: -margin, dy: -margin).intersection(bounds).integral
    }

    func redactionPreview(for annotation: Annotation, rendered: CGImage?) -> CGImage? {
        guard let rendered else { return nil }
        let rect = Self.reviewRect(for: annotation.bounds, in: imageBounds)
        return rendered.cropping(to: rect)
    }
}

struct RedactionReviewSheet: View {
    @ObservedObject var document: EditorDocument
    let onFinish: (Bool) -> Void
    @State private var index = 0
    @State private var rendered: CGImage?

    var body: some View {
        let items = document.redactions
        VStack(spacing: 14) {
            Text("Review Redactions".localized())
                .font(.title3.weight(.semibold))
            if items.isEmpty {
                Text("There are no blurred or pixelated areas.".localized())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let current = items[min(index, items.count - 1)]
                Text(String(format: "Area %d of %d".localized(), min(index, items.count - 1) + 1, items.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Group {
                    if let preview = document.redactionPreview(for: current, rendered: rendered) {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                Text("Make sure nothing private can still be read.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Remove This Area".localized(), role: .destructive) {
                        document.delete([current.id])
                        rendered = document.render()
                        index = max(0, min(index, document.redactions.count - 1))
                    }
                    Spacer()
                    Button("Back".localized()) { index -= 1 }
                        .disabled(index == 0)
                    Button(index >= items.count - 1 ? "Looks Good".localized() : "Next".localized()) {
                        if index >= items.count - 1 { onFinish(true) } else { index += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            HStack {
                Button("Cancel".localized()) { onFinish(false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 560, height: 520)
        .onAppear { rendered = document.render() }
    }
}
