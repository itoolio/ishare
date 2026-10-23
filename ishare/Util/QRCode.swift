import AppKit
import BezelNotification
import CoreImage
import SwiftUI

enum QRCodeRenderer {
    enum CorrectionLevel: String, Sendable {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"
    }

    static func moduleImage(for text: String, correction: CorrectionLevel = .medium) -> CGImage? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent)
    }

    static func scaleFactor(moduleCount: Int, targetPixels: Int) -> Int {
        guard moduleCount > 0 else { return 1 }
        return max(1, targetPixels / moduleCount)
    }

    static func image(for text: String, targetPixels: Int = 512, correction: CorrectionLevel = .medium) -> CGImage? {
        guard let modules = moduleImage(for: text, correction: correction) else { return nil }
        let scale = scaleFactor(moduleCount: modules.width, targetPixels: targetPixels)
        return scaledNearestNeighbor(modules, by: scale)
    }

    static func scaledNearestNeighbor(_ image: CGImage, by scale: Int) -> CGImage? {
        let width = image.width * scale
        let height = image.height * scale
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

struct QRCodeContent: Equatable {
    var url: URL
    var title: String
    var details: [String] = []
    var alternatives: [URL] = []
}

@MainActor
final class QRCodeModel: ObservableObject {
    @Published var content: QRCodeContent
    @Published var selectedURL: URL
    var onStop: (() -> Void)?
    var onClose: () -> Void = {}

    init(content: QRCodeContent, onStop: (() -> Void)?) {
        self.content = content
        selectedURL = content.url
        self.onStop = onStop
    }

    var choices: [URL] {
        [content.url] + content.alternatives.filter { $0 != content.url }
    }
}

struct QRCodeView: View {
    @ObservedObject var model: QRCodeModel

    var body: some View {
        VStack(spacing: 12) {
            Text(model.content.title)
                .font(.headline)
            qrImage
                .frame(width: 220, height: 220)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                .accessibilityLabel("QR Code".localized())
            if model.choices.count > 1 {
                Picker("Address".localized(), selection: $model.selectedURL) {
                    ForEach(model.choices, id: \.self) { url in
                        Text(url.host() ?? url.absoluteString).tag(url)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }
            Text(model.selectedURL.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 260)
            ForEach(model.content.details, id: \.self) { detail in
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let onStop = model.onStop {
                    Button("Stop Sharing".localized(), role: .destructive) {
                        onStop()
                        model.onClose()
                    }
                }
                Spacer()
                Button("Copy".localized()) {
                    HistoryActions.copy(model.selectedURL.absoluteString, announcing: "Copied URL")
                }
                .accessibilityIdentifier("qr.copy")
                Button("Close".localized()) { model.onClose() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("qr.close")
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder private var qrImage: some View {
        if let image = QRCodeRenderer.image(for: model.selectedURL.absoluteString) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
enum QRCodePanel {
    private static var panels: [NSPanel] = []

    static func show(_ url: URL, title: String = "Scan to Open".localized()) {
        show(QRCodeContent(url: url, title: title))
    }

    static func show(_ content: QRCodeContent, onStop: (() -> Void)? = nil) {
        let model = QRCodeModel(content: content, onStop: onStop)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 380),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "QR Code".localized()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: QRCodeView(model: model))
        model.onClose = { [weak panel] in
            panel?.close()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { notification in
            let closed = notification.object as? NSPanel
            Task { @MainActor in
                panels.removeAll { $0 === closed }
            }
        }
        panels.append(panel)
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    static func show(for item: HistoryItem) {
        guard let url = item.preferredURL, !url.isFileURL else {
            BezelNotification.show(messageText: "No link to show".localized(), icon: ToastIcon)
            return
        }
        show(url)
    }
}
