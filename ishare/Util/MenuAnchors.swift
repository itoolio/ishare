import AppKit
import SwiftUI

@MainActor
final class ViewAnchor {
    weak var view: NSView?
}

final class AnchorNSView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let requestor = ContinuityCameraReceiver.shared.validRequestor(forSendType: sendType, returnType: returnType) {
            return requestor
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }
}

struct AnchorReader: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context _: Context) -> AnchorNSView {
        let view = AnchorNSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: AnchorNSView, context _: Context) {
        anchor.view = view
    }
}

extension View {
    func anchored(to anchor: ViewAnchor) -> some View {
        background(AnchorReader(anchor: anchor).allowsHitTesting(false))
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, symbol: String? = nil, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor @objc private func run() {
        handler()
    }
}

@MainActor
enum AppKitMenuPresenter {
    static func popUp(_ menu: NSMenu, from anchor: ViewAnchor) {
        guard let view = anchor.view, let window = view.window else { return }
        let previousResponder = window.firstResponder
        window.makeFirstResponder(view)
        let origin = NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: origin, in: view)
        if window.isVisible, let previousResponder {
            window.makeFirstResponder(previousResponder)
        }
    }
}
