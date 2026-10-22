import AppKit
import BezelNotification
import Defaults
import SwiftUI
import UniformTypeIdentifiers

enum EditorResult: Equatable {
    case saved(URL)
    case discarded
}

@MainActor
final class ImageEditor: NSObject, NSWindowDelegate {
    private static var open: [ImageEditor] = []

    private let document: EditorDocument
    private let fileURL: URL
    private var window: NSWindow?
    private var continuation: CheckedContinuation<EditorResult, Never>?
    private var result: EditorResult

    private init(document: EditorDocument, fileURL: URL) {
        self.document = document
        self.fileURL = fileURL
        result = .saved(fileURL)
    }

    static func edit(fileURL: URL) async -> EditorResult {
        guard let image = ImageEncoder.loadImage(at: fileURL) ?? pdfImage(at: fileURL) else {
            BezelNotification.show(messageText: "Couldn't open the image".localized(), icon: ToastIcon)
            return .saved(fileURL)
        }
        let editor = ImageEditor(document: EditorDocument(image: image, fileURL: fileURL), fileURL: fileURL)
        open.append(editor)
        let result = await editor.present()
        open.removeAll { $0 === editor }
        return result
    }

    static func chooseAndEdit() async {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await editAsNewCapture(sourceURL: url)
    }

    static func editAsNewCapture(sourceURL: URL) async {
        guard let image = ImageEncoder.loadImage(at: sourceURL) ?? pdfImage(at: sourceURL) else {
            BezelNotification.show(messageText: "Couldn't open the image".localized(), icon: ToastIcon)
            return
        }
        do {
            let fileURL = try ImageCaptureFlow.save(CapturedImage(image: image, suffix: "edited"))
            await CaptureSession.finish(fileURL: fileURL, kind: .image, options: CaptureOptions(openEditor: true))
        } catch {
            Log.app.error("Preparing \(sourceURL.lastPathComponent, privacy: .public) for editing failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Couldn't open the image".localized(), icon: ToastIcon)
        }
    }

    private static func pdfImage(at url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: NSScreen.main?.backingScaleFactor ?? 2)])
    }

    private func present() async -> EditorResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let view = EditorView(
                document: document,
                onDone: { [weak self] in self?.save(thenClose: true) },
                onDiscard: { [weak self] in self?.discard() },
                onCopy: { [weak self] in self?.copy() }
            )
            let window = NSWindow(
                contentRect: initialFrame(),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.title = "Editor".localized() + " — " + fileURL.lastPathComponent
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.contentMinSize = CGSize(width: 980, height: 560)
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func initialFrame() -> CGRect {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let imageSize = CGSize(width: document.imageSize.width / scale, height: document.imageSize.height / scale)
        let chromeHeight: CGFloat = 130
        let width = min(max(980, imageSize.width + 80), max(980, visible.width * 0.9))
        let height = min(max(560, imageSize.height + chromeHeight), max(560, visible.height * 0.9))
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    private func save(thenClose: Bool) {
        Log.app.info("Editor save requested, closing: \(thenClose)")
        document.commitText()
        guard document.hasChanges else {
            if thenClose { close(with: .saved(fileURL)) }
            return
        }
        guard let rendered = document.render() else { return }
        let fileType = FileType(rawValue: fileURL.pathExtension.lowercased()) ?? (fileURL.pathExtension.lowercased() == "jpeg" ? .JPG : .PNG)
        do {
            try ImageEncoder.write(rendered, as: fileType, to: fileURL)
            result = .saved(fileURL)
            if thenClose { close(with: .saved(fileURL)) }
        } catch {
            NSLog("Saving edited image failed: %@", error.localizedDescription)
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func discard() {
        close(with: .discarded)
    }

    private func copy() {
        document.commitText()
        guard let rendered = document.render() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: rendered, size: CGSize(width: rendered.width, height: rendered.height))])
        BezelNotification.show(messageText: "Copied to clipboard".localized(), icon: ToastIcon)
    }

    private func close(with result: EditorResult) {
        Log.app.info("Editor closing, window present: \(self.window != nil)")
        self.result = result
        window?.close()
    }

    func windowWillClose(_: Notification) {
        window?.delegate = nil
        window = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}
