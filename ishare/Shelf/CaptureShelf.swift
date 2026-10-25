import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
final class CaptureShelf: ObservableObject {
    static let shared = CaptureShelf()

    @Published private(set) var state = CaptureShelfState()
    @Published var selection = CaptureShelfSelection()
    @Published var isDropTargeted = false
    @Published private(set) var isVisible = false

    private var panel: CaptureShelfPanel?
    private let storage: CaptureShelfStorage

    init(storage: CaptureShelfStorage = .standard) {
        self.storage = storage
    }

    var mode: CaptureShelfMode { Defaults[.captureShelfMode] }

    static func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleCaptureShelf) {
            Task { @MainActor in
                CaptureShelf.shared.toggle()
            }
        }
    }

    func collectCapture(_ fileURL: URL) async {
        guard mode.collectsCaptures else { return }
        await collect([fileURL])
        if mode.showsAfterCapture {
            show()
        }
    }

    func collect(_ urls: [URL]) async {
        let files = ExternalUpload.uploadableFiles(urls)
        guard !files.isEmpty else { return }
        let existingKeys = state.items.flatMap { [$0.sourceKey, CaptureShelfItem.key(for: $0.fileURL)] }
        let fresh = files.filter { !existingKeys.contains(CaptureShelfItem.key(for: $0)) }
        let storage = storage
        let copies = await Task.detached(priority: .userInitiated) {
            fresh.compactMap { source in storage.store(source).map { (source, $0) } }
        }.value
        let stored = copies.map { source, copy in CaptureShelfItem(fileURL: copy, sourceKey: CaptureShelfItem.key(for: source)) }
        let duplicates = files.filter { existingKeys.contains(CaptureShelfItem.key(for: $0)) }.map { CaptureShelfItem(fileURL: $0) }
        let result = state.insert(duplicates + stored)
        discard(result.duplicates.filter { item in stored.contains { $0.id == item.id } } + result.evicted)
        selection.retain(state.items)
    }

    func remove(_ ids: Set<UUID>) {
        discard(state.remove(ids))
        selection.retain(state.items)
        hideIfEmpty()
    }

    func clear() {
        discard(state.clear())
        selection.clear()
        hideIfEmpty()
    }

    func toggle() {
        guard mode != .off else { return }
        isVisible ? hide() : show()
    }

    func show() {
        guard mode != .off else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.present(itemCount: state.items.count)
        isVisible = true
    }

    func hide() {
        panel?.dismiss()
        isVisible = false
    }

    private func hideIfEmpty() {
        if state.isEmpty {
            hide()
        } else {
            panel?.resize(itemCount: state.items.count)
        }
    }

    func preview(items: [CaptureShelfItem]) {
        state = CaptureShelfState(items: items)
        selection.retain(state.items)
    }

    func dragItems(startingAt id: UUID) -> [CaptureShelfItem] {
        state.dragItems(startingAt: id, selection: selection.ids)
    }

    func select(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        selection.click(id, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command), in: state.items)
    }

    func copy(_ item: CaptureShelfItem) {
        PostCapture.copyToClipboard(item.fileURL, kind: item.kind.postCaptureKind)
    }

    func upload(_ item: CaptureShelfItem) {
        Task { @MainActor in
            let before = Defaults[.uploadHistory].first
            await ExternalUpload.upload(fileURL: item.fileURL, keepsLocalCopy: false)
            guard let latest = Defaults[.uploadHistory].first, latest != before else { return }
            state.update(item.id) { $0.link = latest.preferredURL?.absoluteString }
        }
    }

    func openInEditor(_ item: CaptureShelfItem) {
        guard item.kind == .image else { return }
        Task { @MainActor in
            if case let .saved(url) = await ImageEditor.edit(fileURL: item.fileURL), url != item.fileURL {
                state.update(item.id) { $0.fileURL = url }
            }
        }
    }

    func showInFinder(_ item: CaptureShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    func open(_ item: CaptureShelfItem) {
        NSWorkspace.shared.open(item.fileURL)
    }

    private func discard(_ items: [CaptureShelfItem]) {
        let storage = storage
        let urls = items.map(\.fileURL)
        Task.detached(priority: .utility) {
            urls.forEach(storage.removeIfOwned)
        }
    }

    private func makePanel() -> CaptureShelfPanel {
        CaptureShelfPanel(rootView: CaptureShelfView().environmentObject(self))
    }

    func resetStorage() {
        let storage = storage
        Task.detached(priority: .utility) {
            storage.removeAll()
        }
    }
}

struct CaptureShelfStorage: Sendable {
    let directory: URL

    static let standard = CaptureShelfStorage(
        directory: (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appending(path: "CaptureShelf", directoryHint: .isDirectory)
    )

    func owns(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
    }

    func store(_ source: URL) -> URL? {
        if owns(source) { return source }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let target = folder.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            Log.app.error("Adding \(source.lastPathComponent, privacy: .public) to the shelf failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    func removeIfOwned(_ url: URL) {
        guard owns(url) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
