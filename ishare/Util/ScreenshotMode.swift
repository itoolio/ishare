import AppKit
import Defaults
import SwiftUI

enum ScreenshotScene: String, CaseIterable {
    case menu
    case editor
    case uploaders
    case assistant
    case recording
    case history

    var title: String {
        switch self {
        case .menu: "Capture anything"
        case .editor: "Annotate in seconds"
        case .uploaders: "Upload anywhere"
        case .assistant: "Set up uploaders with Apple Intelligence"
        case .recording: "Record exactly what you need"
        case .history: "Every upload at hand"
        }
    }

    var subtitle: String {
        switch self {
        case .menu: "Screenshots, recordings and GIFs from a Control Center style menu"
        case .editor: "Arrows, stamps, spotlight, blur, crop and zoom, built right in"
        case .uploaders: "Imgur, your own server or any S3-compatible storage"
        case .assistant: "Describe your service and get a ready-to-use uploader"
        case .recording: "Regions, windows or displays with webcam, clicks and keystrokes"
        case .history: "Search, copy, edit and delete everything you shared"
        }
    }
}

enum ScreenshotMode {
    static let windowIdentifier = "ishare-screenshot"
    static let testWindowIdentifier = "ishare-uitest"
    static let canvasSize = CGSize(width: 1440, height: 900)

    nonisolated static var isActive: Bool {
        isCapturingScreenshots || isUITesting
    }

    nonisolated static var isCapturingScreenshots: Bool {
        ProcessInfo.processInfo.arguments.contains("-ishareScreenshotMode")
    }

    nonisolated static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ishareUITestMode")
    }

    nonisolated static var skipsOnboarding: Bool {
        isActive || ProcessInfo.processInfo.arguments.contains("-ishareSkipOnboarding")
    }

    nonisolated static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    nonisolated static var scene: ScreenshotScene? {
        argument(after: "-ishareScene").flatMap(ScreenshotScene.init(rawValue:))
    }

    nonisolated static var usesFixtureCapture: Bool {
        isUITesting && argument(after: "-ishareUITestCaptureSource") == "fixture"
    }

    nonisolated static var uploadStubURL: String? {
        guard isUITesting else { return nil }
        return argument(after: "-ishareUITestUploadURL")
    }

    nonisolated static let fixtureCaptureSize = CGSize(width: 1200, height: 750)

    @MainActor static func fixtureCapture() -> CapturedImage? {
        guard usesFixtureCapture,
              let image = sampleImage(size: fixtureCaptureSize, hue: 0.45, title: "UI test capture")
        else { return nil }
        return CapturedImage(image: image, suffix: "fixture", pointScale: 1, source: CaptureSource(appName: "ishare UI tests"))
    }

    @MainActor static var initialSettingsPane: SettingsPane? {
        guard isActive else { return nil }
        switch scene {
        case .uploaders: return .uploaders
        case .recording: return .recording
        default: return argument(after: "-ishareSettingsPane").flatMap(SettingsPane.init(rawValue:))
        }
    }

    nonisolated static let sampleAssistantAnswers = AssistantAnswers(
        service: "Zipline",
        endpoint: "https://share.example.com/api/upload",
        authHeaderName: "Authorization",
        authHeaderValue: "YOUR_API_KEY",
        fileFieldName: "file",
        exampleResponse: #"{"files": [{"url": "https://share.example.com/u/a1b2.png"}]}"#
    )

    nonisolated static let sampleAssistantSpec = GeneratedUploaderSpec(
        name: "zipline", requestURL: "https://share.example.com/api/upload", bodyType: "multipart", fileFormName: "file",
        headerNames: ["Authorization"], headerValues: ["YOUR_API_KEY"], formFieldNames: [], formFieldValues: [],
        responseURL: "{{files[0].url}}", deletionURL: "", deletionMethod: "GET"
    )

    @MainActor private static var window: NSWindow?
    @MainActor private static var editorDocument: EditorDocument?

    @MainActor static func prepareIfNeeded() {
        guard isActive else { return }
        UserDefaults.ishare.removePersistentDomain(forName: SettingsStorage.screenshotSuiteName)
        seedSettings()
        guard let scene else { return }
        if isUITesting {
            presentForTesting(scene)
        } else {
            present(scene)
        }
    }

    @MainActor private static func seedSettings() {
        let zipline = CustomUploader(
            name: "zipline", requestURL: "https://share.example.com/api/upload", headers: ["Authorization": "YOUR_API_KEY"],
            formData: nil, fileFormName: "file", responseURL: "{{files[0].url}}"
        )
        let r2 = CustomUploader.s3(name: "cloudflare r2", configuration: S3Configuration(
            endpoint: "https://account.r2.cloudflarestorage.com", region: "auto", bucket: "screenshots",
            accessKeyId: "ACCESS_KEY", secretAccessKey: "SECRET", keyTemplate: "{{date}}/{{uuid}}.{{ext}}",
            publicURL: "https://img.example.com/{{key}}"
        ))
        let chibisafe = CustomUploader(
            name: "chibisafe", requestURL: "https://chibisafe.example.com/api/upload", headers: ["x-api-key": "API_KEY"],
            formData: nil, fileFormName: "file[]", responseURL: "{{url}}", deletionURL: "{{deleteUrl}}", deleteRequestType: .delete
        )
        Defaults[.savedCustomUploaders] = [zipline, r2, chibisafe]
        Defaults[.activeCustomUploader] = r2.id
        Defaults[.uploadType] = .CUSTOM
        Defaults[.uploadDestination] = .custom(r2.id)
        Defaults[.uploadMedia] = true
        Defaults[.copyToClipboard] = true
        Defaults[.saveToDisk] = true
        Defaults[.openEditorAfterCapture] = true
        Defaults[.builtInShare] = SharingPreferences(airdrop: true, photos: false, messages: false, mail: false)
        Defaults[.recordingResolution] = .p1080
        Defaults[.recordingFrameRate] = .fps60
        Defaults[.compressBeforeUpload] = true
        Defaults[.menuRecordsGIF] = false
        Defaults[.uploadHistory] = sampleHistory()
        if let uploadStubURL {
            seedUploadStub(requestURL: uploadStubURL)
        }
    }

    @MainActor private static func seedUploadStub(requestURL: String) {
        let stub = CustomUploader(
            name: "uitest stub", requestURL: requestURL, headers: nil, formData: nil, fileFormName: "file", responseURL: "{{url}}"
        )
        Defaults[.savedCustomUploaders] = [stub]
        Defaults[.activeCustomUploader] = stub.id
        Defaults[.uploadType] = .CUSTOM
        Defaults[.uploadDestination] = .custom(stub.id)
        Defaults[.additionalUploadDestinations] = []
        Defaults[.uploadMedia] = true
        Defaults[.copyToClipboard] = false
        Defaults[.copyURLAfterUpload] = true
        Defaults[.copyImageToClipboard] = false
        Defaults[.openURLAfterUpload] = false
        Defaults[.saveToDisk] = false
        Defaults[.openEditorAfterCapture] = false
        Defaults[.builtInShare] = SharingPreferences(airdrop: false, photos: false, messages: false, mail: false)
        Defaults[.resultPresentation] = .toast
        Defaults[.toastTimeout] = 60
        Defaults[.uploadHistory] = []
    }

    @MainActor private static func sampleHistory() -> [HistoryItem] {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-screenshots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hues: [CGFloat] = [0.58, 0.75, 0.05, 0.33, 0.9, 0.12, 0.5, 0.66, 0.2, 0.83, 0.42, 0.97]
        return hues.enumerated().map { index, hue in
            let url = directory.appending(path: "sample-\(index).png")
            if let image = sampleImage(size: CGSize(width: 960, height: 600), hue: hue, title: sampleTitles[index % sampleTitles.count]) {
                try? ImageEncoder.write(image, as: .PNG, to: url)
            }
            return HistoryItem(
                fileUrl: "https://img.example.com/2026/10/20/shot-\(index + 1).png", deletionUrl: nil,
                localPath: url.path, date: Date().addingTimeInterval(TimeInterval(-index * 5400))
            )
        }
    }

    private static let sampleTitles = ["Dashboard", "Release notes", "Design review", "Bug report", "Roadmap", "Analytics"]

    nonisolated static func sampleImage(size: CGSize, hue: CGFloat, title: String) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let top = NSColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor
        let bottom = NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.7, alpha: 1).cgColor
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

        let card = CGRect(x: size.width * 0.08, y: size.height * 0.1, width: size.width * 0.84, height: size.height * 0.78)
        context.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        context.addPath(CGPath(roundedRect: card, cornerWidth: 22, cornerHeight: 22, transform: nil))
        context.fillPath()
        context.setFillColor(NSColor.black.withAlphaComponent(0.06).cgColor)
        context.fill(CGRect(x: card.minX, y: card.maxY - 54, width: card.width, height: 54))
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: card.minX + 22 + CGFloat(index) * 24, y: card.maxY - 35, width: 14, height: 14))
        }
        let accent = NSColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1)
        for row in 0 ..< 6 {
            let y = card.maxY - 110 - CGFloat(row) * 62
            context.setFillColor(accent.withAlphaComponent(0.85).cgColor)
            context.fillEllipse(in: CGRect(x: card.minX + 40, y: y, width: 34, height: 34))
            context.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
            let barWidth = card.width * CGFloat([0.62, 0.48, 0.7, 0.4, 0.55, 0.66][row])
            context.addPath(CGPath(roundedRect: CGRect(x: card.minX + 92, y: y + 10, width: barWidth, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil))
            context.fillPath()
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size.height / 26, weight: .bold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.75),
        ]
        NSAttributedString(string: title, attributes: attributes).draw(at: CGPoint(x: card.minX + 104, y: card.maxY - 42))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    @MainActor private static func present(_ scene: ScreenshotScene) {
        let window = ScreenshotWindow(contentRect: CGRect(origin: .zero, size: canvasSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: ScreenshotCanvas(scene: scene, document: document(for: scene)))
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.makeFirstResponder(nil)
        }
    }

    @MainActor private static func presentForTesting(_ scene: ScreenshotScene) {
        let hostingView = NSHostingView(rootView: UITestCanvas(scene: scene, document: testDocument(for: scene)))
        hostingView.sizingOptions = [.minSize]
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: testWindowSize(for: scene, fitting: hostingView.fittingSize)), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(testWindowIdentifier)
        window.title = testWindowIdentifier
        window.setAccessibilityIdentifier(testWindowIdentifier)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        placeInsideVisibleFrame(window)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor private static func placeInsideVisibleFrame(_ window: NSWindow) {
        guard let visible = NSScreen.main?.visibleFrame else {
            window.center()
            return
        }
        let width = min(window.frame.width, visible.width - 20)
        let height = min(window.frame.height, visible.height - 20)
        let origin = CGPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
    }

    @MainActor private static func testWindowSize(for scene: ScreenshotScene, fitting: CGSize) -> CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let preferred = scene == .editor ? CGSize(width: 1000, height: 600) : fitting
        return CGSize(width: min(preferred.width, visible.width - 20), height: min(preferred.height, visible.height - 40))
    }

    @MainActor static func closeTestWindow() {
        window?.close()
        window = nil
        editorDocument = nil
    }

    @MainActor private static func testDocument(for scene: ScreenshotScene) -> EditorDocument? {
        guard scene == .editor, let image = sampleImage(size: CGSize(width: 1600, height: 1000), hue: 0.6, title: "UI test") else { return nil }
        let document = EditorDocument(image: image, fileURL: nil)
        editorDocument = document
        return document
    }

    @MainActor private static func document(for scene: ScreenshotScene) -> EditorDocument? {
        guard scene == .editor, let image = sampleImage(size: CGSize(width: 1800, height: 1120), hue: 0.6, title: "Release checklist") else { return nil }
        let document = EditorDocument(image: image, fileURL: nil)
        document.add(Annotation(shape: .rectangle(CGRect(x: 236, y: 258, width: 860, height: 62)), color: .red, lineWidth: 8))
        document.add(Annotation(shape: .step(CGPoint(x: 200, y: 289), 1), color: .blue, lineWidth: 6, fontSize: 44))
        document.add(Annotation(shape: .blur(CGRect(x: 150, y: 382, width: 960, height: 124)), color: .red, lineWidth: 6))
        document.add(Annotation(shape: .step(CGPoint(x: 200, y: 537), 2), color: .blue, lineWidth: 6, fontSize: 44))
        document.add(Annotation(shape: .highlight(CGRect(x: 236, y: 522, width: 720, height: 32)), color: .yellow, lineWidth: 6))
        document.add(Annotation(shape: .spotlight(CGRect(x: 120, y: 226, width: 1060, height: 356)), color: .white, lineWidth: 4, spotlightShape: .rectangle, dimAmount: 0.45))
        document.add(Annotation(shape: .stamp(CGRect(x: 1110, y: 244, width: 96, height: 96), .emoji("✅")), color: .white, lineWidth: 4))
        document.add(Annotation(shape: .stamp(CGRect(x: 980, y: 500, width: 76, height: 76), .symbol("star.fill")), color: .yellow, lineWidth: 4))
        document.add(Annotation(shape: .curvedArrow(CGPoint(x: 1540, y: 760), CGPoint(x: 1560, y: 420), CGPoint(x: 1230, y: 300)), color: .red, lineWidth: 10))
        document.add(Annotation(shape: .callout(CGPoint(x: 1060, y: 640), CGRect(x: 1140, y: 830, width: 420, height: 120), "Ship it!"), color: .red, lineWidth: 6, fontSize: 64))
        document.tool = .arrow
        editorDocument = document
        return document
    }
}

final class ScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct ScreenshotCanvas: View {
    let scene: ScreenshotScene
    let document: EditorDocument?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.09, blue: 0.24), Color(red: 0.07, green: 0.27, blue: 0.47), Color(red: 0.1, green: 0.52, blue: 0.58)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(.white.opacity(0.12)).frame(width: 700).offset(x: -520, y: 360).blur(radius: 40)
            Circle().fill(.cyan.opacity(0.18)).frame(width: 520).offset(x: 560, y: -340).blur(radius: 50)
            content
        }
        .frame(width: ScreenshotMode.canvasSize.width, height: ScreenshotMode.canvasSize.height)
        .environment(\.colorScheme, .dark)
    }

    private var caption: some View {
        VStack(alignment: scene == .menu ? .leading : .center, spacing: 12) {
            Text(scene.title.localized())
                .font(.system(size: 50, weight: .bold, design: .rounded))
            Text(scene.subtitle.localized())
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(scene == .menu ? .leading : .center)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .menu:
            HStack(spacing: 70) {
                caption.frame(width: 520, alignment: .leading)
                MainMenuView()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
                    .scaleEffect(1.45)
                    .frame(width: 464, height: 640)
            }
        case .editor:
            VStack(spacing: 30) {
                caption
                if let document {
                    framed(EditorView(document: document, onDone: {}, onDiscard: {}, onCopy: {}), size: CGSize(width: 1180, height: 640))
                }
            }
        case .uploaders, .recording:
            VStack(spacing: 34) {
                caption
                framed(SettingsView(), size: CGSize(width: 760, height: 560))
            }
        case .assistant:
            VStack(spacing: 18) {
                caption
                framed(UploaderAssistantSheet { _ in }, size: CGSize(width: 620, height: 690))
            }
        case .history:
            VStack(spacing: 34) {
                caption
                framed(HistoryGridView(), size: CGSize(width: 980, height: 420))
            }
        }
    }

    private func framed(_ view: some View, size: CGSize) -> some View {
        view
            .frame(width: size.width, height: size.height)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 34, y: 16)
    }
}

struct UITestCanvas: View {
    let scene: ScreenshotScene
    let document: EditorDocument?

    var body: some View {
        switch scene {
        case .menu:
            if ScreenshotMode.uploadStubURL != nil {
                VStack(spacing: 0) {
                    MainMenuView()
                    HistoryStateProbe()
                }
            } else {
                MainMenuView()
            }
        case .editor:
            if let document {
                VStack(spacing: 0) {
                    EditorView(document: document, onDone: { ScreenshotMode.closeTestWindow() }, onDiscard: { ScreenshotMode.closeTestWindow() }, onCopy: {})
                    EditorStateProbe(document: document)
                }
                .frame(width: 1100, height: 760)
            }
        case .uploaders, .recording:
            SettingsView()
                .frame(width: 760, height: 560)
        case .assistant:
            UploaderAssistantSheet { _ in }
                .frame(width: 620, height: 690)
        case .history:
            HistoryGridView()
                .frame(width: 980, height: 420)
        }
    }
}

struct EditorStateProbe: View {
    @ObservedObject var document: EditorDocument

    private var summary: String {
        "annotations=\(document.annotations.count) undo=\(document.canUndo) redo=\(document.canRedo) tool=\(document.tool.rawValue)"
    }

    var body: some View {
        Text(summary)
            .font(.system(size: 10).monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityValue(summary)
            .accessibilityIdentifier("uitest.editor.state")
    }
}

struct HistoryStateProbe: View {
    @Default(.uploadHistory) private var uploadHistory

    private var summary: String {
        "history=\(uploadHistory.count) latest=\(uploadHistory.first?.fileUrl ?? "none")"
    }

    var body: some View {
        Text(summary)
            .font(.system(size: 10).monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityValue(summary)
            .accessibilityIdentifier("uitest.history.state")
    }
}
