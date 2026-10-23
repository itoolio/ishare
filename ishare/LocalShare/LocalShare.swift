import AppKit
import BezelNotification
import Defaults
import Foundation

struct LocalShare: Equatable, Sendable {
    let entry: LocalShareEntry
    let urls: [URL]

    var url: URL { urls[0] }
    var alternatives: [URL] { Array(urls.dropFirst()) }
}

@MainActor
final class LocalShareManager {
    static let shared = LocalShareManager()

    static let maxDownloadChoices = [0, 1, 3, 10]

    let server: LocalShareServer
    private let storageDirectory: URL
    private let interfaces: () -> [LocalNetworkInterface]
    private var expiryTasks: [String: Task<Void, Never>] = [:]

    init(
        server: LocalShareServer = LocalShareServer(),
        storageDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "LocalShares", directoryHint: .isDirectory),
        interfaces: @escaping () -> [LocalNetworkInterface] = { LocalNetworkAddress.interfaces() }
    ) {
        self.server = server
        self.storageDirectory = storageDirectory
        self.interfaces = interfaces
    }

    var activeShares: [LocalShareEntry] {
        server.activeEntries
    }

    func share(
        fileURL: URL, expiry: LocalShareExpiry = Defaults[.localShareExpiry], maxDownloads: Int? = Defaults[.localShareMaxDownloads]
    ) async throws -> LocalShare {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else { throw LocalShareError.unreadableFile }
        let port = try await server.start()
        let token = LocalShareRequest.makeToken()
        let directory = storageDirectory.appending(path: token, directoryHint: .isDirectory)
        let copy = directory.appending(path: fileURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fileURL, to: copy)
        } catch {
            throw LocalShareError.unreadableFile
        }
        let entry = server.add(fileURL: copy, expiry: expiry, maxDownloads: maxDownloads, token: token)
        let urls = LocalNetworkAddress.urls(port: port, path: entry.path, interfaces: interfaces())
        guard !urls.isEmpty else {
            stop(token: token)
            throw LocalShareError.noNetworkAddress
        }
        scheduleExpiry(of: entry)
        Log.upload.info("Sharing \(fileURL.lastPathComponent, privacy: .public) on the local network at port \(port)")
        return LocalShare(entry: entry, urls: urls)
    }

    func stop(token: String) {
        expiryTasks.removeValue(forKey: token)?.cancel()
        server.remove(token: token)
        try? FileManager.default.removeItem(at: storageDirectory.appending(path: token, directoryHint: .isDirectory))
        stopServerIfIdle()
    }

    func stop(url: URL) {
        guard let token = url.pathComponents.dropFirst().first, server.entry(for: token) != nil else { return }
        stop(token: token)
    }

    func stopAll() {
        expiryTasks.values.forEach { $0.cancel() }
        expiryTasks.removeAll()
        server.stop()
        try? FileManager.default.removeItem(at: storageDirectory)
    }

    func purgeUnavailable() {
        for entry in server.removeUnavailable() {
            stop(token: entry.token)
        }
    }

    private func stopServerIfIdle() {
        if server.activeEntries.isEmpty {
            server.stop()
        }
    }

    private func scheduleExpiry(of entry: LocalShareEntry) {
        let token = entry.token
        expiryTasks[token] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                guard let current = server.entry(for: token), current.isAvailable(at: Date()) else {
                    stop(token: token)
                    return
                }
            }
        }
    }

    static func details(for entry: LocalShareEntry, now: Date = Date()) -> [String] {
        var details: [String] = []
        if let expiresAt = entry.expiresAt {
            details.append(String(format: "Available until %@".localized(), expiresAt.formatted(date: .omitted, time: .shortened)))
        } else {
            details.append("Available until ishare quits".localized())
        }
        if let maxDownloads = entry.maxDownloads {
            details.append(String(format: "Up to %d downloads".localized(), maxDownloads))
        }
        details.append("Devices must be on the same network.".localized())
        return details
    }

    func present(_ share: LocalShare) {
        let content = QRCodeContent(
            url: share.url, title: "Shared on Local Network".localized(),
            details: Self.details(for: share.entry), alternatives: share.alternatives
        )
        QRCodePanel.show(content) { [weak self] in
            self?.stop(token: share.entry.token)
        }
    }

    func shareAndPresent(fileURL: URL) async {
        do {
            let share = try await share(fileURL: fileURL)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(share.url.absoluteString, forType: .string)
            present(share)
        } catch {
            Log.upload.error("Local network sharing failed: \(error.localizedDescription, privacy: .public)")
            ToastController.showMessage(
                title: "Couldn’t share on the local network".localized(),
                message: error.localizedDescription,
                symbol: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }
}

@MainActor
struct LocalNetworkUploader: Uploader {
    nonisolated static let displayName = "Local Network"
    var manager: LocalShareManager = .shared

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let share = try await manager.share(fileURL: fileURL)
        progress(1)
        manager.present(share)
        return UploadOutcome(url: share.url, deletionURL: nil, uploaderID: nil, s3Key: nil, isLocalNetwork: true)
    }

    func delete(_ item: HistoryItem) async throws {
        if let url = item.remoteURL {
            manager.stop(url: url)
        }
    }
}

extension HistoryActions {
    static func canShareOnLocalNetwork(_ item: HistoryItem) -> Bool {
        item.existingLocalFileURL != nil
    }

    static func shareOnLocalNetwork(_ item: HistoryItem) {
        guard let file = item.existingLocalFileURL else { return }
        Task { @MainActor in
            await LocalShareManager.shared.shareAndPresent(fileURL: file)
        }
    }

    static func showQRCode(_ item: HistoryItem) {
        MenuController.shared.perform {
            QRCodePanel.show(for: item)
        }
    }
}
