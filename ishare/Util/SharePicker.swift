import AppKit
import SwiftUI

@MainActor
enum SharePicker {
    static func items(for item: HistoryItem) -> [Any] {
        if let file = item.existingLocalFileURL {
            return [file]
        }
        return item.remoteURL.map { [$0] } ?? []
    }

    static func items(for items: [HistoryItem]) -> [Any] {
        items.flatMap { self.items(for: $0) }
    }

    static func show(_ items: [Any], from anchor: ViewAnchor, edge: NSRectEdge = .minY) {
        guard !items.isEmpty, let view = anchor.view else { return }
        NSSharingServicePicker(items: items).show(relativeTo: view.bounds, of: view, preferredEdge: edge)
    }
}

struct ShareActionButton: View {
    let items: () -> [Any]
    var iconOnly = false
    let identifier: String
    @State private var anchor = ViewAnchor()

    var body: some View {
        ToastActionButton(symbol: "square.and.arrow.up", title: "Share…", iconOnly: iconOnly, identifier: identifier) {
            SharePicker.show(items(), from: anchor)
        }
        .anchored(to: anchor)
    }
}
