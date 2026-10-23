import AppKit
import Defaults
import ishareCore

@MainActor
enum DestinationChooser {
    static func isRequested(
        flags: NSEvent.ModifierFlags = NSEvent.modifierFlags,
        modifier: ForceUploadModifier? = Defaults[.destinationChooserModifier]
    ) -> Bool {
        guard let modifier else { return false }
        return flags.intersection(.deviceIndependentFlagsMask).contains(modifier.modifierFlag)
    }

    static func entries() -> [(title: String, target: UploadTarget)] {
        [("Imgur", UploadTarget.imgur(clientID: Defaults[.imgurClientId]))]
            + CustomUploader.allCases.map { ($0.name, UploadTarget.custom($0)) }
            + [("Local Network".localized(), UploadTarget.localNetwork)]
    }

    static func choose(at location: NSPoint = NSEvent.mouseLocation) -> UploadTarget? {
        let options = entries()
        let handler = MenuSelectionHandler()
        let menu = NSMenu(title: "Upload to".localized())
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "Upload to".localized(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (index, option) in options.enumerated() {
            let item = NSMenuItem(title: option.title, action: #selector(MenuSelectionHandler.select(_:)), keyEquivalent: "")
            item.target = handler
            item.tag = index
            menu.addItem(item)
        }
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: location, in: nil)
        return handler.selectedIndex.flatMap { options.indices.contains($0) ? options[$0].target : nil }
    }
}

@MainActor
private final class MenuSelectionHandler: NSObject {
    var selectedIndex: Int?

    @objc func select(_ sender: NSMenuItem) {
        selectedIndex = sender.tag
    }
}
