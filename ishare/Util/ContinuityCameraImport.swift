import AppKit
import BezelNotification

enum ContinuityCameraImport {
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")]

    static func accepts(sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Bool {
        guard sendType == nil, let returnType else { return false }
        return imageTypes.contains(returnType) || NSImage.imageTypes.contains(returnType.rawValue)
    }

    static func image(from pasteboard: NSPasteboard) -> CGImage? {
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    @MainActor static func importImage(_ image: CGImage) async {
        do {
            let fileURL = try ImageCaptureFlow.save(CapturedImage(image: image, suffix: "iphone"))
            Log.capture.info("Imported a Continuity Camera image to \(fileURL.path, privacy: .public)")
            await CaptureSession.finish(fileURL: fileURL, kind: .image)
        } catch {
            Log.capture.error("Saving the Continuity Camera image failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Couldn't import the image".localized(), icon: ToastIcon)
        }
    }

    @MainActor static func menuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Import from iPhone".localized())
        let importItem = NSMenuItem(title: "Import from iPhone".localized(), action: nil, keyEquivalent: "")
        importItem.identifier = NSMenuItem.importFromDeviceIdentifier
        submenu.addItem(importItem)
        submenu.addItem(.separator())
        let hint = NSMenuItem(title: "Take Photo, Scan Documents or Add Sketch with a nearby iPhone or iPad".localized(), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        submenu.addItem(hint)
        let item = NSMenuItem(title: "Import from iPhone".localized(), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
        item.submenu = submenu
        item.setAccessibilityIdentifier("menu.importFromDevice")
        return item
    }
}

@MainActor
final class ContinuityCameraReceiver: NSResponder, @preconcurrency NSServicesMenuRequestor {
    static let shared = ContinuityCameraReceiver()

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        ContinuityCameraImport.accepts(sendType: sendType, returnType: returnType) ? self : nil
    }

    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        guard let image = ContinuityCameraImport.image(from: pasteboard) else { return false }
        Task {
            await ContinuityCameraImport.importImage(image)
        }
        return true
    }

    func writeSelection(to _: NSPasteboard, types _: [NSPasteboard.PasteboardType]) -> Bool {
        false
    }
}
