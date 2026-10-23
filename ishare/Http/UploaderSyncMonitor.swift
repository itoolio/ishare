import BezelNotification
import Defaults
import Foundation
import ishareCore

struct UploaderConflict: Equatable {
    let local: CustomUploader
    let incomingCopy: CustomUploader
    let incomingID: UUID
}

enum UploaderSyncMerge {
    struct Result {
        var merged: [CustomUploader]
        var conflicts: [UploaderConflict]
        var restoredLocal: [CustomUploader]

        var changesIncoming: Bool { !conflicts.isEmpty || !restoredLocal.isEmpty }
    }

    static func merge(
        local: [CustomUploader], incoming: [CustomUploader], lastSync: Date, copySuffix: String,
        makeID: () -> UUID = UUID.init
    ) -> Result {
        var merged = incoming
        var conflicts: [UploaderConflict] = []
        var restored: [CustomUploader] = []
        let incomingByID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for uploader in local where (uploader.modifiedAt ?? .distantPast) > lastSync {
            guard let remote = incomingByID[uploader.id] else {
                merged.append(uploader)
                restored.append(uploader)
                continue
            }
            guard !remote.hasSameContent(as: uploader) else { continue }
            let copy = remote.renamed("\(remote.name) \(copySuffix)").withID(makeID())
            merged.removeAll { $0.id == uploader.id }
            merged.append(uploader)
            merged.append(copy)
            conflicts.append(UploaderConflict(local: uploader, incomingCopy: copy, incomingID: remote.id))
        }
        return Result(merged: merged, conflicts: conflicts, restoredLocal: restored)
    }
}

@MainActor
final class UploaderSyncMonitor {
    static let shared = UploaderSyncMonitor()
    static let remoteWindow: TimeInterval = 30

    private var snapshot: [CustomUploader] = []
    private var pendingRemote: (snapshot: [CustomUploader], deadline: Date)?
    private var isApplyingMerge = false
    private var observer: (any NSObjectProtocol)?
    private var updates: Task<Void, Never>?

    func start() {
        guard SettingsStorage.syncsToCloud, observer == nil else { return }
        snapshot = Array(Defaults[.savedCustomUploaders] ?? [])
        if Defaults[.uploadersLastSyncedAt] == nil {
            Defaults[.uploadersLastSyncedAt] = Date()
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated {
                self?.remoteChanged(keys: keys)
            }
        }
        updates = Task { [weak self] in
            for await value in Defaults.updates(.savedCustomUploaders, initial: false) {
                self?.uploadersChanged(value)
            }
        }
    }

    private func remoteChanged(keys: [String]) {
        guard keys.contains(Defaults.Keys.savedCustomUploaders.name) else { return }
        pendingRemote = (snapshot, Date().addingTimeInterval(Self.remoteWindow))
    }

    private func uploadersChanged(_ value: Set<CustomUploader>?) {
        defer { snapshot = Array(Defaults[.savedCustomUploaders] ?? []) }
        guard !isApplyingMerge else { return }
        guard let pending = pendingRemote, pending.deadline > Date() else {
            pendingRemote = nil
            return
        }
        pendingRemote = nil
        let result = UploaderSyncMerge.merge(
            local: pending.snapshot, incoming: Array(value ?? []), lastSync: Defaults[.uploadersLastSyncedAt] ?? .distantPast,
            copySuffix: "(from other Mac)".localized()
        )
        Defaults[.uploadersLastSyncedAt] = Date()
        guard result.changesIncoming else { return }
        for conflict in result.conflicts {
            S3SecretStore.copySecret(from: conflict.incomingID, to: conflict.incomingCopy.id)
            UploaderSecrets.copySecrets(from: conflict.incomingID, to: conflict.incomingCopy.id)
        }
        isApplyingMerge = true
        Defaults[.savedCustomUploaders] = Set(result.merged)
        isApplyingMerge = false
        notify(result.conflicts)
    }

    private func notify(_ conflicts: [UploaderConflict]) {
        guard let first = conflicts.first else { return }
        let message =
            conflicts.count == 1
            ? String(format: "“%@” was also changed on another Mac. Both versions were kept.".localized(), first.local.name)
            : String(format: "%d uploaders were also changed on another Mac. Both versions were kept.".localized(), conflicts.count)
        BezelNotification.show(messageText: message, icon: ToastIcon)
    }
}
