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

    static let cookieBannerScript = """
        (() => {
          const reject = /^(reject( all)?|decline( all)?|deny( all)?|only (necessary|essential)|necessary only|use necessary cookies only|refuse|ablehnen|alle ablehnen|tout refuser|rechazar( todo)?|rifiuta( tutto)?)$/i;
          const accept = /^(accept( all)?|agree|allow( all)?|ok|got it|i agree|alle akzeptieren|akzeptieren|tout accepter|aceptar( todo)?|accetta( tutto)?)$/i;
          const known = ['#onetrust-reject-all-handler', '#CybotCookiebotDialogBodyButtonDecline', '#didomi-notice-disagree-button', '.qc-cmp2-summary-buttons button[mode="secondary"]', '#truste-consent-required', '.cc-deny', '[data-testid="uc-deny-all-button"]', '#onetrust-accept-btn-handler', '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll', '#didomi-notice-agree-button', '.cc-dismiss', '[data-testid="uc-accept-all-button"]'];
          for (const selector of known) {
            const element = document.querySelector(selector);
            if (element) { element.click(); return 'clicked'; }
          }
          const buttons = Array.from(document.querySelectorAll('button, [role="button"], a'));
          const label = (element) => (element.innerText || element.getAttribute('aria-label') || '').trim();
          const target = buttons.find((element) => reject.test(label(element))) || buttons.find((element) => accept.test(label(element)));
          if (target) { target.click(); return 'clicked'; }
          let removed = 0;
          for (const element of document.querySelectorAll('div, section, aside, dialog')) {
            const style = getComputedStyle(element);
            if ((style.position === 'fixed' || style.position === 'sticky') && /cookie|consent|gdpr|privacy/i.test(element.id + ' ' + element.className + ' ' + (element.innerText || '').slice(0, 400))) {
              element.remove();
              removed += 1;
            }
          }
          if (removed) { document.documentElement.style.overflow = 'auto'; document.body && (document.body.style.overflow = 'auto'); }
          return removed ? 'removed' : 'none';
        })();
        """

    static func capture(_ url: URL, width: WebPageWidth) async throws -> CGImage {
        try await capture(url, request: WebPageCaptureRequest(address: url.absoluteString, width: width.points))
    }

    static func capture(_ url: URL, request: WebPageCaptureRequest) async throws -> CGImage {
        let capture = WebPageCapture(width: request.width)
        defer { capture.window.close() }
        try await capture.load(url, dismissingBanners: request.dismissesCookieBanners)
        return try await capture.snapshot()
    }

    static func pdf(_ url: URL, request: WebPageCaptureRequest) async throws -> Data {
        let capture = WebPageCapture(width: request.width)
        defer { capture.window.close() }
        try await capture.load(url, dismissingBanners: request.dismissesCookieBanners)
        return try await capture.webView.pdf(configuration: WKPDFConfiguration())
    }

    private func load(_ url: URL, dismissingBanners: Bool) async throws {
        window.orderBack(nil)
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }
        try await Task.sleep(for: Self.settleDelay)
        if dismissingBanners {
            let result = try? await webView.evaluateJavaScript(Self.cookieBannerScript)
            Log.capture.info("Cookie banner: \((result as? String) ?? "none", privacy: .public)")
            if (result as? String) != "none" {
                try await Task.sleep(for: Self.settleDelay)
            }
        }
    }

    private func snapshot() async throws -> CGImage {
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
        await promptForRequest()
    }

    private static func promptForRequest() async {
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
        widths.addItem(withTitle: "Custom width".localized())
        let customWidth = NSTextField(string: "1280")
        customWidth.placeholderString = "1280"
        customWidth.frame.size.width = 80
        let widthRow = NSStackView(views: [widths, customWidth, NSTextField(labelWithString: "pt")])
        let formats = NSPopUpButton()
        formats.addItems(withTitles: ["Image".localized(), "PDF".localized()])
        formats.selectItem(at: Defaults[.webCaptureFormat] == .pdf ? 1 : 0)
        let banners = NSButton(checkboxWithTitle: "Dismiss cookie banners".localized(), target: nil, action: nil)
        banners.state = Defaults[.webCaptureDismissesCookieBanners] ? .on : .off
        let stack = NSStackView(views: [field, widthRow, formats, banners])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = CGRect(x: 0, y: 0, width: 320, height: 118)
        field.frame.size.width = 320
        alert.accessoryView = stack
        alert.addButton(withTitle: "Capture".localized())
        alert.addButton(withTitle: "Cancel".localized())
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let presets = WebPageWidth.allCases
        let index = max(0, widths.indexOfSelectedItem)
        let width = index < presets.count ? presets[index].points : WebPageCapturePlan.width(from: customWidth.stringValue) ?? WebPageWidth.desktop.points
        let format: WebPageFormat = formats.indexOfSelectedItem == 1 ? .pdf : .image
        Defaults[.webCaptureFormat] = format
        Defaults[.webCaptureDismissesCookieBanners] = banners.state == .on
        await capture(WebPageCaptureRequest(address: field.stringValue, width: width, format: format, dismissesCookieBanners: banners.state == .on))
    }

    @discardableResult
    static func capture(_ address: String, width: WebPageWidth, options: CaptureOptions = .standard) async -> URL? {
        await capture(WebPageCaptureRequest(address: address, width: width.points, dismissesCookieBanners: Defaults[.webCaptureDismissesCookieBanners]), options: options)
    }

    @discardableResult
    static func capture(_ request: WebPageCaptureRequest, options: CaptureOptions = .standard) async -> URL? {
        guard let url = WebPageCapturePlan.normalizedURL(from: request.address) else {
            BezelNotification.show(messageText: WebPageCaptureError.invalidAddress.localizedDescription, icon: ToastIcon)
            return nil
        }
        CaptureAgain.remember(
            .webPage(address: request.address, width: request.width, pdf: request.format == .pdf, dismissesCookieBanners: request.dismissesCookieBanners))
        do {
            if request.format == .pdf {
                return try await deliverPDF(try await WebPageCapture.pdf(url, request: request), host: url.host() ?? "web", options: options)
            }
            let image = try await WebPageCapture.capture(url, request: request)
            let captured = CapturedImage(image: image, suffix: url.host() ?? "web", pointScale: 2, source: CaptureSource(appName: url.host()))
            return await CaptureSession.deliverCapture(captured, options: options)
        } catch {
            Log.capture.error("Web page capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: error.localizedDescription, icon: ToastIcon)
            return nil
        }
    }
}

extension WebPageCaptureFlow {
    static func deliverPDF(_ data: Data, host: String, options: CaptureOptions) async throws -> URL {
        let fileName = CaptureFileName.make(prefix: Defaults[.captureFileName], suffix: host, ext: "pdf")
        let url = ImageCaptureFlow.availableURL(SaveLocation.fileURL(for: .captures, fileName: fileName))
        try data.write(to: url, options: .atomic)
        if let resultHandler = options.resultHandler {
            resultHandler(url)
            return url
        }
        await CaptureSession.finish(fileURL: url, kind: .image, options: options)
        return url
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
