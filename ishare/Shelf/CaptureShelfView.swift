import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureShelfView: View {
    @EnvironmentObject private var shelf: CaptureShelf
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if shelf.state.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveGlass(cornerRadius: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: shelf.isDropTargeted ? 2 : 0)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $shelf.isDropTargeted) { providers in
            CaptureShelfDrop.collect(providers, into: shelf)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: shelf.state.items.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture Shelf".localized())
        .accessibilityIdentifier("shelf")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("Shelf".localized())
                .font(.system(size: 12, weight: .semibold))
            if !shelf.state.isEmpty {
                Text(shelf.state.items.count, format: .number)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                shelf.clear()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(shelf.state.isEmpty)
            .helpAndAccessibilityLabel("Clear".localized())
            .accessibilityIdentifier("shelf.clear")
            Button {
                shelf.hide()
            } label: {
                Image(systemName: "xmark")
            }
            .helpAndAccessibilityLabel("Close".localized())
            .accessibilityIdentifier("shelf.close")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: CaptureShelfGeometry.headerHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Drop files here".localized())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: CaptureShelfGeometry.itemSpacing) {
                ForEach(shelf.state.items) { item in
                    CaptureShelfItemView(item: item, isSelected: shelf.selection.contains(item.id))
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(CaptureShelfGeometry.itemSpacing)
        }
        .scrollIndicators(.never)
    }
}

struct CaptureShelfItemView: View {
    let item: CaptureShelfItem
    let isSelected: Bool
    @EnvironmentObject private var shelf: CaptureShelf

    var body: some View {
        thumbnail
            .help(item.fileName)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.fileName)
            .accessibilityValue(item.link ?? "")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .modifier(CaptureShelfItemActions(item: item, shelf: shelf))
            .accessibilityIdentifier("shelf.item")
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.primary.opacity(0.06))
            ThumbnailImage(key: ThumbnailKey.forFile(item.fileURL, pointSize: CaptureShelfGeometry.width)) { failed in
                if failed {
                    Image(systemName: item.kind == .video ? "video.fill" : "doc")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            badges
        }
        .frame(height: CaptureShelfGeometry.itemHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        }
        .overlay {
            CaptureShelfDragSource(itemID: item.id)
        }
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if item.kind == .video {
                Image(systemName: "play.fill")
            }
            if item.link != nil {
                Image(systemName: "link")
            }
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, item.kind == .video || item.link != nil ? 5 : 0)
        .padding(.vertical, 3)
        .background(.black.opacity(item.kind == .video || item.link != nil ? 0.5 : 0), in: Capsule())
        .padding(6)
        .accessibilityHidden(true)
    }
}

struct CaptureShelfItemActions: ViewModifier {
    let item: CaptureShelfItem
    let shelf: CaptureShelf

    func body(content: Content) -> some View {
        content
            .accessibilityAction { shelf.open(item) }
            .accessibilityAction(named: Text("Copy".localized())) { shelf.copy(item) }
            .accessibilityAction(named: Text("Upload".localized())) { shelf.upload(item) }
            .accessibilityAction(named: Text("Open in Editor".localized())) { shelf.openInEditor(item) }
            .accessibilityAction(named: Text("Show in Finder".localized())) { shelf.showInFinder(item) }
            .accessibilityAction(named: Text("Remove".localized())) { shelf.remove([item.id]) }
    }
}

enum CaptureShelfDrop {
    @MainActor static func collect(_ providers: [NSItemProvider], into shelf: CaptureShelf) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in
                    await shelf.collect([url])
                }
            }
        }
        return !fileProviders.isEmpty
    }
}

struct CaptureShelfDragSource: NSViewRepresentable {
    let itemID: UUID

    func makeNSView(context _: Context) -> CaptureShelfDragSourceView {
        CaptureShelfDragSourceView(itemID: itemID)
    }

    func updateNSView(_ view: CaptureShelfDragSourceView, context _: Context) {
        view.itemID = itemID
    }
}

@MainActor
final class CaptureShelfDragSourceView: NSView, NSDraggingSource {
    var itemID: UUID
    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    init(itemID: UUID) {
        self.itemID = itemID
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    private var shelf: CaptureShelf { CaptureShelf.shared }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isDragging = false
        if event.clickCount == 2, let item = shelf.state.item(itemID) {
            shelf.open(item)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownEvent else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 3 else { return }
        isDragging = true
        if !shelf.selection.contains(itemID) {
            shelf.select(itemID, modifiers: [])
        }
        beginDrag(with: start)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !isDragging, event.clickCount <= 1 else { return }
        shelf.select(itemID, modifiers: event.modifierFlags)
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        guard let item = shelf.state.item(itemID) else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Copy".localized(), symbol: "doc.on.doc") { [shelf] in shelf.copy(item) })
        menu.addItem(ClosureMenuItem(title: "Upload".localized(), symbol: "icloud.and.arrow.up") { [shelf] in shelf.upload(item) })
        if item.kind == .image {
            menu.addItem(ClosureMenuItem(title: "Open in Editor".localized(), symbol: "pencil.and.scribble") { [shelf] in shelf.openInEditor(item) })
        }
        menu.addItem(ClosureMenuItem(title: "Show in Finder".localized(), symbol: "folder") { [shelf] in shelf.showInFinder(item) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Remove".localized(), symbol: "minus.circle") { [shelf] in shelf.remove([item.id]) })
        return menu
    }

    private func beginDrag(with event: NSEvent) {
        let items = shelf.dragItems(startingAt: itemID)
        guard !items.isEmpty else { return }
        let draggingItems = items.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(pasteboardWriter: CaptureShelfPasteboardWriter(item: item))
            let offset = CGFloat(index) * 6
            draggingItem.setDraggingFrame(bounds.offsetBy(dx: offset, dy: -offset), contents: Self.dragImage(for: item, size: bounds.size))
            return draggingItem
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.copy, .generic]
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        isDragging = false
        mouseDownEvent = nil
    }

    private static func dragImage(for item: CaptureShelfItem, size: CGSize) -> NSImage {
        if item.kind == .image, let image = ImageProcessing.thumbnail(for: item.fileURL, maxPixelSize: Int(max(size.width, size.height) * 2)) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: item.fileURL.path)
    }
}

final class CaptureShelfPasteboardWriter: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let fileURL: URL
    let link: String?

    init(item: CaptureShelfItem) {
        fileURL = item.fileURL
        link = item.link
        super.init()
        fileType = (UTType(filenameExtension: item.fileURL.pathExtension) ?? .data).identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        types.append(.fileURL)
        if link != nil {
            types.append(.URL)
            types.append(.string)
        }
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            return (fileURL as NSURL).pasteboardPropertyList(forType: type)
        case .URL:
            return link.flatMap(URL.init(string:)).flatMap { ($0 as NSURL).pasteboardPropertyList(forType: type) }
        case .string:
            return link
        default:
            return super.pasteboardPropertyList(forType: type)
        }
    }

    nonisolated func filePromiseProvider(_: NSFilePromiseProvider, fileNameForType _: String) -> String {
        fileURL.lastPathComponent
    }

    nonisolated func filePromiseProvider(_: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: fileURL, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
