import AVFoundation
import Defaults
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ToastModel: ObservableObject {
    let fileURL: URL
    let thumbnail: NSImage
    let isImage: Bool
    @Published var isHovering = false
    @Published var isDragging = false
    var onDismiss: () -> Void = {}
    var onEdit: () -> Void = {}

    init(fileURL: URL, thumbnail: NSImage, isImage: Bool) {
        self.fileURL = fileURL
        self.thumbnail = thumbnail
        self.isImage = isImage
    }
}

struct ToastPopoverView: View {
    @ObservedObject var model: ToastModel
    @Default(.saveToDisk) var saveToDisk

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: model.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrag {
                    model.isDragging = true
                    let provider = NSItemProvider(object: model.fileURL as NSURL)
                    provider.suggestedName = model.fileURL.lastPathComponent
                    return provider
                }
                .onTapGesture {
                    if saveToDisk {
                        NSWorkspace.shared.activateFileViewerSelecting([model.fileURL])
                    }
                    model.onDismiss()
                }

            if model.isHovering {
                AdaptiveGlassContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        if model.isImage {
                            toastButton("pencil.tip.crop.circle", help: "Open in Editor") { model.onEdit() }
                        }
                        toastButton("doc.on.doc", help: "Copy to Clipboard") {
                            PostCapture.copyToClipboard(model.fileURL, kind: model.isImage ? .image : .video)
                        }
                        if saveToDisk {
                            toastButton("folder", help: "Open in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([model.fileURL])
                            }
                        }
                        toastButton("xmark", help: "Close") { model.onDismiss() }
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .adaptiveGlass(cornerRadius: 18)
        .opacity(model.isDragging ? 0.3 : 1)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.2)) {
                model.isHovering = hovering
            }
        }
        .frame(width: 320, height: 220)
    }

    private func toastButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .adaptiveGlassCapsule(interactive: true)
        .help(help.localized())
    }
}

@MainActor
final class ToastController {
    private static var visible: [ToastController] = []
    private let window: NSWindow
    private let model: ToastModel
    private var continuation: CheckedContinuation<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    private init(model: ToastModel) {
        self.model = model
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: ToastPopoverView(model: model))
    }

    static func show(fileURL: URL, thumbnail: NSImage, isImage: Bool) async {
        let controller = ToastController(model: ToastModel(fileURL: fileURL, thumbnail: thumbnail, isImage: isImage))
        visible.append(controller)
        await controller.present()
        visible.removeAll { $0 === controller }
    }

    private func present() async {
        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onEdit = { [weak self] in
            guard let self else { return }
            let url = model.fileURL
            dismiss()
            Task { @MainActor in
                _ = await ImageEditor.edit(fileURL: url)
            }
        }
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(Self.visible.count - 1) * 232
        window.setFrameOrigin(NSPoint(x: screen.maxX - window.frame.width - 20, y: screen.maxY - window.frame.height - 20 - offset))
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }, completionHandler: nil)
        scheduleDismiss()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let timeout = Defaults[.toastTimeout]
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled else { return }
            if model.isHovering {
                while model.isHovering, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        guard let continuation else { return }
        self.continuation = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [window] in
            Task { @MainActor in
                window.orderOut(nil)
            }
        })
        continuation.resume()
    }
}

@MainActor
func showToast(fileURL: URL) async {
    let isVideo = ["mov", "mp4"].contains(fileURL.pathExtension.lowercased())
    let thumbnail: NSImage?
    if isVideo {
        thumbnail = await videoThumbnail(for: fileURL)
    } else {
        thumbnail = ImageProcessing.thumbnail(for: fileURL, maxPixelSize: 640) ?? NSImage(contentsOf: fileURL)
    }
    guard let thumbnail else { return }
    await ToastController.show(fileURL: fileURL, thumbnail: thumbnail, isImage: !isVideo && fileURL.pathExtension.lowercased() != "gif")
}

@MainActor
func showToast(fileURL: URL, completion: (@Sendable () -> Void)? = nil) {
    Task { @MainActor in
        await showToast(fileURL: fileURL)
        completion?()
    }
}

func videoThumbnail(for url: URL) async -> NSImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 640, height: 640)
    for seconds in [1.0, 0.0] {
        if let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
            return NSImage(cgImage: result.image, size: CGSize(width: result.image.width, height: result.image.height))
        }
    }
    return nil
}
