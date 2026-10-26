import AVFoundation
import Defaults
import SwiftUI

@MainActor
func showToast(fileURL: URL) async {
    await showToast(fileURL: fileURL, awaitingUpload: false)
}

@MainActor
func showToast(fileURL: URL, awaitingUpload: Bool) async {
    let model = makeToastModel(fileURL: fileURL, awaitingUpload: awaitingUpload)
    if awaitingUpload {
        model.followUpload()
    }
    await presentToast(model)
}

@MainActor
func beginUploadToast(fileURL: URL) -> (model: ToastModel, presentation: Task<Void, Never>) {
    let model = makeToastModel(fileURL: fileURL, awaitingUpload: true)
    model.followUpload(resolvesExplicitly: true)
    return (model, Task { @MainActor in await presentToast(model) })
}

@MainActor
private func makeToastModel(fileURL: URL, awaitingUpload: Bool) -> ToastModel {
    let isImage = HistoryItemKind(fileExtension: fileURL.pathExtension) == .image && fileURL.pathExtension.lowercased() != "gif"
    let item = awaitingUpload ? nil : uploadedItem(for: fileURL)
    return ToastModel(fileURL: fileURL, isImage: isImage, historyItem: item)
}

@MainActor
private func presentToast(_ model: ToastModel) async {
    if let fileURL = model.fileURL {
        let key = ThumbnailKey.forFile(fileURL, pointSize: 64)
        var thumbnail = ThumbnailCache.shared.cachedImage(for: key)
        if thumbnail == nil {
            thumbnail = await ThumbnailCache.shared.image(for: key)
        }
        model.thumbnail = thumbnail ?? NSWorkspace.shared.icon(forFile: fileURL.path)
        Log.app.info("Presenting the result for \(fileURL.lastPathComponent, privacy: .public)")
    }
    await ResultPresenter.present(model)
}

@MainActor
private func uploadedItem(for fileURL: URL) -> HistoryItem? {
    if let match = Defaults[.uploadHistory].prefix(10).first(where: { $0.localPath == fileURL.path }) {
        return match
    }
    guard let recent = UploadManager.shared.recentlyCompletedItem(within: 3), recent.localPath == nil else { return nil }
    return recent
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
