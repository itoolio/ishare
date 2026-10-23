import SwiftUI

struct LayersSidebar: View {
    static let width: CGFloat = 232

    @ObservedObject var document: EditorDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers".localized())
                    .font(.headline)
                Spacer()
                Text(verbatim: "\(document.annotations.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if document.annotations.isEmpty {
                Text("No annotations yet".localized())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List(selection: selection) {
                    ForEach(document.layers) { layer in
                        LayerRow(document: document, layer: layer)
                            .tag(layer.id)
                    }
                    .onMove { source, destination in
                        document.moveLayers(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("editor.layers.list")
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
        .accessibilityIdentifier("editor.layers")
    }

    private var selection: Binding<Set<UUID>> {
        Binding(
            get: { document.selectedIDs },
            set: { ids in
                document.commitText()
                document.selectedIDs = ids
            }
        )
    }
}

private struct LayerRow: View {
    @ObservedObject var document: EditorDocument
    var layer: Annotation

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: layer.layerSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: layer.color.nsColor))
                .frame(width: 18)
            Text(verbatim: document.label(for: layer))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(layer.hidden ? .secondary : .primary)
            Spacer(minLength: 4)
            iconButton(
                symbol: layer.hidden ? "eye.slash" : "eye",
                help: layer.hidden ? "Show".localized() : "Hide".localized(),
                identifier: "editor.layers.visibility",
                active: layer.hidden
            ) {
                document.setHidden(!layer.hidden, for: [layer.id])
            }
            iconButton(
                symbol: layer.locked ? "lock.fill" : "lock.open",
                help: layer.locked ? "Unlock".localized() : "Lock".localized(),
                identifier: "editor.layers.lock",
                active: layer.locked
            ) {
                document.setLocked(!layer.locked, for: [layer.id])
            }
            iconButton(symbol: "trash", help: "Delete".localized(), identifier: "editor.layers.delete", active: false) {
                document.delete([layer.id])
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: document.label(for: layer)))
        .accessibilityIdentifier("editor.layers.row")
    }

    private func iconButton(symbol: String, help: String, identifier: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 18, height: 18)
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(identifier)
    }
}
