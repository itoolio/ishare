import AppKit
import BezelNotification
import Defaults
import ishareCore
import WebKit

enum WebPageCaptureError: LocalizedError {
    case invalidAddress
    case loadFailed(String)
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter a web address that starts with http or https".localized()
        case let .loadFailed(reason): String(format: "The page couldn't be loaded: %@".localized(), reason)
        case .snapshotFailed: "The page couldn't be captured".localized()
        }
    }
}

@MainActor
final class WebPageCapture: NSObject, WKNavigationDelegate {
    static let viewportHeight: CGFloat = 900
    static let settleDelay: Duration = .milliseconds(800)

    private let webView: WKWebView
    private let window: NSWindow
    private var navigation: CheckedContinuation<Void, Error>?

    init(width: CGFloat) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let frame = CGRect(x: 0, y: 0, width: width, height: Self.viewportHeight)
        webView = WKWebView(frame: frame, configuration: configuration)
        window = NSWindow(contentRect: frame.offsetBy(dx: -20000, dy: -20000), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.sharingType = .none
    }

    static func capture(_ url: URL, width: WebPageWidth) async throws -> CGImage {
        let capture = WebPageCapture(width: width.points)
        defer { capture.window.close() }
        return try await capture.run(url)
    }

    private func run(_ url: URL) async throws -> CGImage {
        window.orderBack(nil)
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }
        try await Task.sleep(for: Self.settleDelay)
        let height = try await documentHeight()
        for stop in WebPageCapturePlan.scrollStops(height: height, viewport: Self.viewportHeight) {
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, \(Int(stop)))")
            try await Task.sleep(for: .milliseconds(150))
        }
        let fullHeight = WebPageCapturePlan.cappedHeight(try await documentHeight())
        webView.setFrameSize(CGSize(width: webView.frame.width, height: fullHeight))
        window.setContentSize(webView.frame.size)
        try await Task.sleep(for: Self.settleDelay)
        var pieces: [CGImage] = []
        for chunk in WebPageCapturePlan.chunks(height: fullHeight) {
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: chunk.minY, width: webView.frame.width, height: chunk.height)
            configuration.afterScreenUpdates = true
            let image = try await webView.takeSnapshot(configuration: configuration)
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw WebPageCaptureError.snapshotFailed }
            pieces.append(cgImage)
        }
        guard let stitched = Self.stack(pieces) else { throw WebPageCaptureError.snapshotFailed }
        return stitched
    }

    private func documentHeight() async throws -> CGFloat {
        let value = try await webView.evaluateJavaScript("Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)")
        return CGFloat((value as? NSNumber)?.doubleValue ?? Double(Self.viewportHeight))
    }

    static func stack(_ images: [CGImage]) -> CGImage? {
        guard let width = images.map(\.width).max(), width > 0 else { return nil }
        let height = images.reduce(0) { $0 + $1.height }
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var top = height
        for image in images {
            top -= image.height
            context.draw(image, in: CGRect(x: 0, y: top, width: image.width, height: image.height))
        }
        return context.makeImage()
    }

    nonisolated func webView(_: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor in resume(with: nil) }
    }

    nonisolated func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in resume(with: message) }
    }

    nonisolated func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in resume(with: message) }
    }

    private func resume(with failure: String?) {
        guard let navigation else { return }
        self.navigation = nil
        if let failure {
            navigation.resume(throwing: WebPageCaptureError.loadFailed(failure))
        } else {
            navigation.resume()
        }
    }
}

@MainActor
enum WebPageCaptureFlow {
    static func prompt() async {
        let clipboard = NSPasteboard.general.string(forType: .string).flatMap(WebPageCapturePlan.normalizedURL(from:))
        let alert = NSAlert()
        alert.messageText = "Capture Web Page".localized()
        alert.informativeText = "ishare loads the page out of sight and captures its full length.".localized()
        let field = NSTextField(string: clipboard?.absoluteString ?? "")
        field.placeholderString = "https://example.com"
        let widths = NSPopUpButton()
        for width in WebPageWidth.allCases {
            widths.addItem(withTitle: width.title)
        }
        let stack = NSStackView(views: [field, widths])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = CGRect(x: 0, y: 0, width: 320, height: 56)
        field.frame.size.width = 320
        alert.accessoryView = stack
        alert.addButton(withTitle: "Capture".localized())
        alert.addButton(withTitle: "Cancel".localized())
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let width = WebPageWidth.allCases[max(0, widths.indexOfSelectedItem)]
        await capture(field.stringValue, width: width)
    }

    @discardableResult
    static func capture(_ address: String, width: WebPageWidth, options: CaptureOptions = .standard) async -> URL? {
        guard let url = WebPageCapturePlan.normalizedURL(from: address) else {
            BezelNotification.show(messageText: WebPageCaptureError.invalidAddress.localizedDescription, icon: ToastIcon)
            return nil
        }
        do {
            let image = try await WebPageCapture.capture(url, width: width)
            let captured = CapturedImage(image: image, suffix: url.host() ?? "web", pointScale: 2, source: CaptureSource(appName: url.host()))
            return await CaptureSession.deliverCapture(captured, options: options)
        } catch {
            Log.capture.error("Web page capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: error.localizedDescription, icon: ToastIcon)
            return nil
        }
    }
}

extension WebPageWidth {
    var title: String {
        switch self {
        case .desktop: "Desktop (1440 pt)".localized()
        case .tablet: "Tablet (834 pt)".localized()
        case .mobile: "Phone (390 pt)".localized()
        }
    }
}
