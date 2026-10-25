import AppKit
import Defaults
import ishareCore
import SwiftUI

enum GuideScene: String, CaseIterable, Sendable {
    case capture
    case editor
    case region
    case shelf

    static let framesPerSecond = 15
    static let advanceKey = "]"

    var duration: Double {
        switch self {
        case .capture: 6.5
        case .editor: 6
        case .region: 6
        case .shelf: 6.5
        }
    }

    var frameCount: Int { Int((duration * Double(Self.framesPerSecond)).rounded()) }

    var title: String {
        switch self {
        case .capture: "Capture anything"
        case .editor: "Annotate in seconds"
        case .region: "Select exactly what you need"
        case .shelf: "Keep captures at hand"
        }
    }

    var subtitle: String {
        switch self {
        case .capture: "Pick a capture from the menu and get a link right away"
        case .editor: "Draw arrows, shapes and numbered steps on any screenshot"
        case .region: "Crosshair guides, a magnifier and exact dimensions while you drag"
        case .shelf: "Collect recent captures at the edge of the screen and drag them anywhere"
        }
    }
}

@MainActor
final class GuideClock: ObservableObject {
    @Published private(set) var frame = 0
    let scene: GuideScene
    weak var window: NSWindow?
    private var monitor: Any?

    init(scene: GuideScene) {
        self.scene = scene
    }

    var time: Double { Double(frame) / Double(GuideScene.framesPerSecond) }

    func start() {
        publish()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.charactersIgnoringModifiers == GuideScene.advanceKey else { return event }
            MainActor.assumeIsolated { self?.advance() }
            return nil
        }
    }

    func advance() {
        frame = min(frame + 1, scene.frameCount)
        publish()
    }

    private func publish() {
        window?.setAccessibilityValue("frame=\(frame) of=\(scene.frameCount)")
    }
}

enum GuideTimeline {
    static func progress(_ time: Double, from start: Double, to end: Double) -> Double {
        guard end > start else { return time >= end ? 1 : 0 }
        return min(1, max(0, (time - start) / (end - start)))
    }

    static func eased(_ value: Double) -> Double {
        value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
    }

    static func interpolate(_ from: CGPoint, _ to: CGPoint, _ amount: Double) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * amount, y: from.y + (to.y - from.y) * amount)
    }
}

@MainActor
enum GuideMode {
    static var scene: GuideScene? {
        guard ScreenshotMode.isCapturingScreenshots else { return nil }
        return ScreenshotMode.argument(after: "-ishareGuideScene").flatMap(GuideScene.init(rawValue:))
    }

    private static var window: NSWindow?
    private static var clock: GuideClock?

    static func present(_ scene: GuideScene) {
        let clock = GuideClock(scene: scene)
        let window = ScreenshotWindow(contentRect: CGRect(origin: .zero, size: ScreenshotMode.canvasSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(ScreenshotMode.windowIdentifier)
        window.title = ScreenshotMode.windowIdentifier
        window.setAccessibilityIdentifier(ScreenshotMode.windowIdentifier)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: GuideCanvas(clock: clock).appModel())
        window.center()
        clock.window = window
        clock.start()
        self.window = window
        self.clock = clock
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct GuideCanvas: View {
    @ObservedObject var clock: GuideClock

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.09, blue: 0.24), Color(red: 0.07, green: 0.27, blue: 0.47), Color(red: 0.1, green: 0.52, blue: 0.58)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 28) {
                caption
                stage
                    .frame(width: 1240, height: 680)
            }
        }
        .frame(width: ScreenshotMode.canvasSize.width, height: ScreenshotMode.canvasSize.height)
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
    }

    private var caption: some View {
        VStack(spacing: 8) {
            Text(clock.scene.title.localized())
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(clock.scene.subtitle.localized())
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    @ViewBuilder
    private var stage: some View {
        switch clock.scene {
        case .capture: GuideCaptureStage(time: clock.time)
        case .editor: GuideEditorStage(time: clock.time)
        case .region: GuideRegionStage(time: clock.time)
        case .shelf: GuideShelfStage(time: clock.time)
        }
    }
}

struct GuideCursor: View {
    let position: CGPoint
    var pressed = false

    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(.black, .white)
            .symbolRenderingMode(.palette)
            .scaleEffect(pressed ? 0.85 : 1, anchor: .topLeading)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .position(x: position.x + 10, y: position.y + 14)
            .allowsHitTesting(false)
    }
}

struct GuideDesktop: View {
    let hue: CGFloat
    let title: String

    var body: some View {
        Group {
            if let image = ScreenshotMode.sampleImage(size: CGSize(width: 1240, height: 680), hue: hue, title: title) {
                Image(decorative: image, scale: 1)
                    .resizable()
            } else {
                Color.gray
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
    }
}

struct GuideCaptureStage: View {
    let time: Double

    private let tile = CGPoint(x: 905, y: 170)
    private let selectionStart = CGPoint(x: 260, y: 170)
    private let selectionEnd = CGPoint(x: 820, y: 500)

    var body: some View {
        let menuIn = GuideTimeline.eased(GuideTimeline.progress(time, from: 0.2, to: 0.6))
        let menuOut = GuideTimeline.progress(time, from: 1.6, to: 1.9)
        let drag = GuideTimeline.eased(GuideTimeline.progress(time, from: 2.2, to: 3.4))
        let flash = 1 - GuideTimeline.progress(time, from: 3.6, to: 3.9)
        let toastIn = GuideTimeline.eased(GuideTimeline.progress(time, from: 3.9, to: 4.4))
        ZStack(alignment: .topLeading) {
            GuideDesktop(hue: 0.62, title: "Release notes")
            if time >= 2 && time < 3.7 {
                Color.black.opacity(0.35)
                selectionOverlay(drag: drag)
            }
            if time >= 3.6 {
                Color.white.opacity(0.6 * flash)
            }
            MainMenuView()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .scaleEffect(0.96 + 0.04 * menuIn, anchor: .topTrailing)
                .opacity(menuIn * (1 - menuOut))
                .offset(x: 860, y: 16)
            if toastIn > 0 {
                toast
                    .opacity(toastIn)
                    .offset(x: 1240 - ToastCardView.width - 24 + (1 - toastIn) * 40, y: 680 - 150)
            }
            GuideCursor(position: cursor, pressed: (time > 1.45 && time < 1.6) || (time > 2.2 && time < 3.4))
        }
        .frame(width: 1240, height: 680, alignment: .topLeading)
        .clipped()
    }

    private var cursor: CGPoint {
        if time < 1.5 {
            return GuideTimeline.interpolate(CGPoint(x: 560, y: 420), tile, GuideTimeline.eased(GuideTimeline.progress(time, from: 0.4, to: 1.4)))
        }
        if time < 2.2 {
            return GuideTimeline.interpolate(tile, selectionStart, GuideTimeline.eased(GuideTimeline.progress(time, from: 1.7, to: 2.2)))
        }
        return GuideTimeline.interpolate(selectionStart, selectionEnd, GuideTimeline.eased(GuideTimeline.progress(time, from: 2.2, to: 3.4)))
    }

    private func selectionOverlay(drag: Double) -> some View {
        let end = GuideTimeline.interpolate(selectionStart, selectionEnd, drag)
        let rect = CGRect(x: selectionStart.x, y: selectionStart.y, width: max(1, end.x - selectionStart.x), height: max(1, end.y - selectionStart.y))
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            Text("\(Int(rect.width * 2)) × \(Int(rect.height * 2))")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.7), in: Capsule())
                .offset(x: rect.maxX - 90, y: rect.maxY + 10)
        }
    }

    private var toast: some View {
        let image = ScreenshotMode.sampleImage(size: CGSize(width: 320, height: 200), hue: 0.62, title: "Release notes").map {
            NSImage(cgImage: $0, size: CGSize(width: 160, height: 100))
        }
        let model = ToastModel(
            fileURL: URL(fileURLWithPath: "/tmp/ishare-guide.png"), isImage: true, thumbnail: image,
            historyItem: HistoryItem(fileUrl: "https://img.example.com/2026/10/25/release-notes.png", date: Date())
        )
        return ToastCardView(model: model)
            .frame(width: ToastCardView.width)
    }
}

struct GuideEditorStage: View {
    let time: Double
    @StateObject private var document = GuideEditorStage.makeDocument()

    private static let arrowStart = CGPoint(x: 1480, y: 820)
    private static let arrowEnd = CGPoint(x: 1010, y: 330)

    private static func makeDocument() -> EditorDocument {
        let image = ScreenshotMode.sampleImage(size: CGSize(width: 1800, height: 1120), hue: 0.6, title: "Release checklist")!
        let document = EditorDocument(image: image, fileURL: nil)
        document.tool = .arrow
        return document
    }

    var body: some View {
        EditorView(document: document, onDone: {}, onDiscard: {}, onCopy: {})
            .frame(width: 1240, height: 680)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
            .onAppear { update(time) }
            .onChange(of: time) { _, time in update(time) }
    }

    private func update(_ time: Double) {
        var annotations: [Annotation] = []
        let arrow = GuideTimeline.eased(GuideTimeline.progress(time, from: 0.6, to: 2.2))
        if arrow > 0 {
            let end = GuideTimeline.interpolate(Self.arrowStart, Self.arrowEnd, arrow)
            annotations.append(Annotation(shape: .arrow(Self.arrowStart, end), color: .red, lineWidth: 10))
        }
        let box = GuideTimeline.eased(GuideTimeline.progress(time, from: 2.6, to: 3.8))
        if box > 0 {
            annotations.append(Annotation(shape: .rectangle(CGRect(x: 236, y: 258, width: 860 * box, height: 62)), color: .red, lineWidth: 8))
        }
        if time >= 4.2 {
            annotations.append(Annotation(shape: .step(CGPoint(x: 200, y: 289), 1), color: .blue, lineWidth: 6, fontSize: 44))
        }
        if time >= 4.7 {
            annotations.append(Annotation(shape: .step(CGPoint(x: 200, y: 537), 2), color: .blue, lineWidth: 6, fontSize: 44))
        }
        if annotations != document.annotations {
            document.replaceAnnotations(with: annotations)
        }
    }
}

struct GuideRegionStage: View {
    let time: Double

    private let hover = CGPoint(x: 430, y: 240)
    private let start = CGPoint(x: 300, y: 160)
    private let end = CGPoint(x: 900, y: 520)

    var body: some View {
        let drag = GuideTimeline.eased(GuideTimeline.progress(time, from: 2.4, to: 4.4))
        let cursor = cursorPosition
        ZStack(alignment: .topLeading) {
            GuideDesktop(hue: 0.08, title: "Design review")
            Color.black.opacity(0.3)
            if time >= 2.4 {
                selection(drag: drag)
            }
            guides(at: cursor)
            magnifier(at: cursor)
                .opacity(time < 4.6 ? 1 : 1 - GuideTimeline.progress(time, from: 4.6, to: 4.9))
            GuideCursor(position: cursor, pressed: time >= 2.4 && time < 4.4)
        }
        .frame(width: 1240, height: 680, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cursorPosition: CGPoint {
        if time < 2.4 {
            let wander = GuideTimeline.eased(GuideTimeline.progress(time, from: 0.3, to: 1.6))
            let settle = GuideTimeline.eased(GuideTimeline.progress(time, from: 1.6, to: 2.3))
            return GuideTimeline.interpolate(GuideTimeline.interpolate(CGPoint(x: 700, y: 420), hover, wander), start, settle)
        }
        return GuideTimeline.interpolate(start, end, GuideTimeline.eased(GuideTimeline.progress(time, from: 2.4, to: 4.4)))
    }

    private func guides(at point: CGPoint) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white.opacity(0.55)).frame(width: 1240, height: 1).offset(y: point.y)
            Rectangle().fill(.white.opacity(0.55)).frame(width: 1, height: 680).offset(x: point.x)
        }
    }

    private func selection(drag: Double) -> some View {
        let current = GuideTimeline.interpolate(start, end, drag)
        let rect = CGRect(x: start.x, y: start.y, width: max(1, current.x - start.x), height: max(1, current.y - start.y))
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 2))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            Text("\(Int(rect.width * 2)) × \(Int(rect.height * 2))")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.7), in: Capsule())
                .offset(x: rect.minX, y: rect.maxY + 10)
        }
    }

    private func magnifier(at point: CGPoint) -> some View {
        let size: CGFloat = 120
        return GuideDesktop(hue: 0.08, title: "Design review")
            .frame(width: 1240, height: 680)
            .scaleEffect(4, anchor: UnitPoint(x: point.x / 1240, y: point.y / 680))
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .overlay(Rectangle().fill(Color.accentColor).frame(width: 6, height: 6))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .offset(x: point.x + 24, y: point.y + 24)
    }
}

struct GuideShelfStage: View {
    let time: Double
    @StateObject private var shelf = GuideShelfStage.makeShelf()

    private static let titles = ["Dashboard", "Bug report", "Roadmap", "Analytics"]
    private static let appearances = [0.4, 1.0, 1.6, 2.2]

    private static func makeShelf() -> CaptureShelf {
        CaptureShelf(storage: CaptureShelfStorage(directory: FileManager.default.temporaryDirectory.appending(path: "ishare-guide-shelf", directoryHint: .isDirectory)))
    }

    private static func sampleFile(_ index: Int) -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-guide-shelf-samples", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(titles[index].lowercased().replacingOccurrences(of: " ", with: "-")).png")
        if !FileManager.default.fileExists(atPath: url.path),
            let image = ScreenshotMode.sampleImage(size: CGSize(width: 480, height: 300), hue: [0.58, 0.05, 0.33, 0.83][index], title: titles[index])
        {
            try? ImageEncoder.write(image, as: .PNG, to: url)
        }
        return url
    }

    var body: some View {
        let dragOut = GuideTimeline.eased(GuideTimeline.progress(time, from: 3.6, to: 5.0))
        let shelfFrame = CGRect(x: 1240 - CaptureShelfGeometry.width - 16, y: 70, width: CaptureShelfGeometry.width, height: 500)
        let grab = CGPoint(x: shelfFrame.midX, y: shelfFrame.minY + CaptureShelfGeometry.headerHeight + 54)
        let drop = CGPoint(x: 420, y: 380)
        let cursor =
            time < 3.6
            ? GuideTimeline.interpolate(CGPoint(x: 760, y: 520), grab, GuideTimeline.eased(GuideTimeline.progress(time, from: 2.8, to: 3.5)))
            : GuideTimeline.interpolate(grab, drop, dragOut)
        ZStack(alignment: .topLeading) {
            GuideDesktop(hue: 0.75, title: "Weekly update")
            composeWindow(highlighted: dragOut > 0.7, dropped: time >= 5.0)
                .offset(x: 150, y: 150)
            CaptureShelfView()
                .environmentObject(shelf)
                .frame(width: shelfFrame.width, height: CaptureShelfGeometry.contentHeight(itemCount: shelf.state.items.count, in: CGRect(x: 0, y: 0, width: 1240, height: 600)))
                .offset(x: shelfFrame.minX, y: shelfFrame.minY)
            if time >= 3.6 && time < 5.0, let first = shelf.state.items.first {
                ThumbnailImage(key: ThumbnailKey.forFile(first.fileURL, pointSize: 120)) { _ in Color.clear }
                    .frame(width: 120, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(0.85)
                    .shadow(radius: 8)
                    .position(x: cursor.x - 10, y: cursor.y - 10)
            }
            GuideCursor(position: cursor, pressed: time >= 3.6 && time < 5.0)
        }
        .frame(width: 1240, height: 680, alignment: .topLeading)
        .clipped()
        .onAppear { update(time) }
        .onChange(of: time) { _, time in update(time) }
    }

    private func composeWindow(highlighted: Bool, dropped: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Message").font(.system(size: 15, weight: .semibold))
            Divider()
            Text("Here's this week's dashboard:").font(.system(size: 14))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                .overlay {
                    if dropped, let first = shelf.state.items.first {
                        ThumbnailImage(key: ThumbnailKey.forFile(first.fileURL, pointSize: 240)) { _ in Color.clear }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(10)
                    }
                }
                .frame(height: 200)
        }
        .padding(18)
        .frame(width: 540)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private func update(_ time: Double) {
        let visible = Self.appearances.filter { $0 <= time }.count
        guard visible != shelf.state.items.count else { return }
        shelf.preview(items: (0 ..< visible).reversed().map { CaptureShelfItem(fileURL: Self.sampleFile($0), addedAt: Date(timeIntervalSince1970: Double($0))) })
    }
}
