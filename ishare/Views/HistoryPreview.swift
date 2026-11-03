import AppKit
import CryptoKit
import Foundation
import Quartz

enum HistoryPreview {
    static func previewableURL(for item: HistoryItem) -> URL? {
        item.existingLocalFileURL ?? cachedRemoteURL(for: item).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    static func urls(for items: [HistoryItem]) -> [URL] {
        items.compactMap(previewableURL(for:))
    }

    static func startURL(selected: [HistoryItem], visible: [HistoryItem]) -> URL? {
        (selected + visible).lazy.compactMap(previewableURL(for:)).first
    }

    static func cachedRemoteURL(for item: HistoryItem) -> URL? {
        guard let remote = item.preferredURL, remote.scheme == "https" || remote.scheme == "http" else { return nil }
        let digest = SHA256.hash(data: Data(remote.absoluteString.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let name = digest + "-" + remote.lastPathComponent
        return cacheDirectory.appending(path: name, directoryHint: .notDirectory)
    }

    static var cacheDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "ishare-history-preview", directoryHint: .isDirectory)
    }

    static func downloadRemoteFiles(for items: [HistoryItem]) async {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for item in items where item.existingLocalFileURL == nil {
            guard let remote = item.preferredURL, let target = cachedRemoteURL(for: item), !FileManager.default.fileExists(atPath: target.path) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(from: remote),
                (response as? HTTPURLResponse)?.statusCode == 200, data.count < 200_000_000
            else { continue }
            try? data.write(to: target)
        }
    }
}

@MainActor
final class HistoryQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = HistoryQuickLook()
    static let toggleRequest = Notification.Name("dev.adrian.ishare.history.toggleQuickLook")

    private(set) var urls: [URL] = []
    private var startIndex = 0

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggle(urls: [URL], start: URL?) {
        if isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        guard !urls.isEmpty else { return }
        self.urls = urls
        startIndex = start.flatMap(urls.firstIndex(of:)) ?? 0
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = startIndex
        panel.reloadData()
    }

    func end(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[safe: index] as NSURL? }
    }

    static func shouldToggle(on event: NSEvent, in window: NSWindow?) -> Bool {
        guard event.keyCode == 49, event.window === window, window?.isKeyWindow == true, !event.isARepeat else { return false }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty else { return false }
        return !(window?.firstResponder is NSText)
    }
}
