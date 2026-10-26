import AppKit

@MainActor
enum AnnotationContextMenu {
    static func make(for document: EditorDocument, pasteboard: AnnotationStylePasteboard = .shared) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copy = ClosureMenuItem(title: "Copy Style".localized(), keyEquivalent: "c") { document.copyStyle(to: pasteboard) }
        copy.keyEquivalentModifierMask = [.command, .option]
        copy.isEnabled = document.canCopyStyle
        menu.addItem(copy)
        let paste = ClosureMenuItem(title: "Paste Style".localized(), keyEquivalent: "v") { document.pasteStyle(from: pasteboard) }
        paste.keyEquivalentModifierMask = [.command, .option]
        paste.isEnabled = document.canPasteStyle(from: pasteboard)
        menu.addItem(paste)
        if let source = document.selectedAnnotation, !source.styleProperties.isEmpty {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: EditorDocument.useAsDefaultTitle(for: source)) { document.useAsDefault(source) })
        }
        return menu
    }
}
