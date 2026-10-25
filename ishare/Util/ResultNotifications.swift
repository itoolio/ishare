import AppKit
import Defaults
import SwiftUI
import UserNotifications

struct ResultNotificationPayload: Equatable, Sendable {
    static let urlKey = "url"
    static let pathKey = "path"

    let url: String?
    let path: String?

    init(url: String?, path: String?) {
        self.url = url
        self.path = path
    }

    init(userInfo: [AnyHashable: Any]) {
        url = userInfo[Self.urlKey] as? String
        path = userInfo[Self.pathKey] as? String
    }

    var userInfo: [String: String] {
        var info: [String: String] = [:]
        info[Self.urlKey] = url
        info[Self.pathKey] = path
        return info
    }

    var fileURL: URL? {
        path.map { URL(fileURLWithPath: $0) }
    }

    var categoryIdentifier: String {
        let canEdit = fileURL.map { HistoryItemKind(fileExtension: $0.pathExtension) == .image && $0.pathExtension.lowercased() != "gif" } ?? false
        return canEdit ? ResultNotifier.editableCategory : ResultNotifier.linkCategory
    }
}

enum ResultNotificationAction: String, Sendable {
    case copy = "dev.adrian.ishare.notification.copy"
    case open = "dev.adrian.ishare.notification.open"
    case edit = "dev.adrian.ishare.notification.edit"
    case openUploaderSettings = "dev.adrian.ishare.notification.openUploaderSettings"
    case testUploader = "dev.adrian.ishare.notification.testUploader"
}

@MainActor
final class ResultNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ResultNotifier()
    nonisolated static let editableCategory = "dev.adrian.ishare.result.editable"
    nonisolated static let linkCategory = "dev.adrian.ishare.result.link"
    nonisolated static let healthCategory = "dev.adrian.ishare.maintenance.health"

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
        let copy = UNNotificationAction(identifier: ResultNotificationAction.copy.rawValue, title: "Copy URL".localized())
        let open = UNNotificationAction(identifier: ResultNotificationAction.open.rawValue, title: "Open".localized(), options: [.foreground])
        let edit = UNNotificationAction(identifier: ResultNotificationAction.edit.rawValue, title: "Edit".localized(), options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.editableCategory, actions: [copy, open, edit], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.linkCategory, actions: [copy, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.healthCategory, actions: Self.healthActions, intentIdentifiers: []),
        ])
    }

    static var healthActions: [UNNotificationAction] {
        [
            UNNotificationAction(identifier: ResultNotificationAction.openUploaderSettings.rawValue, title: "Open Settings".localized(), options: [.foreground]),
            UNNotificationAction(identifier: ResultNotificationAction.testUploader.rawValue, title: "Test Now".localized()),
        ]
    }

    func postMessage(title: String, body: String, category: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category {
            content.categoryIdentifier = category
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Log.app.error("Posting the maintenance notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func canPost() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    func post(title: String, body: String, payload: ResultNotificationPayload, thumbnail: NSImage?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = payload.userInfo
        content.categoryIdentifier = payload.categoryIdentifier
        if let attachment = thumbnail.flatMap(Self.attachment(for:)) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Log.app.error("Posting the result notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func attachment(for image: NSImage) -> UNNotificationAttachment? {
        guard let tiff = image.tiffRepresentation,
            let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "notification-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "thumbnail", url: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    static func handle(action identifier: String, payload: ResultNotificationPayload) {
        switch ResultNotificationAction(rawValue: identifier) {
        case .copy:
            copy(payload)
        case .edit:
            guard let file = payload.fileURL, FileManager.default.fileExists(atPath: file.path) else {
                open(payload)
                return
            }
            Task { @MainActor in
                await ImageEditor.editAsNewCapture(sourceURL: file)
            }
        case .open:
            open(payload)
        case .openUploaderSettings:
            MenuController.shared.openSettings(pane: .uploaders)
        case .testUploader:
            Task { @MainActor in
                await UploaderHealthCheck.run(forced: true)
            }
        case nil where identifier == UNNotificationDefaultActionIdentifier:
            open(payload)
        case nil:
            break
        }
    }

    private static func copy(_ payload: ResultNotificationPayload) {
        NSPasteboard.general.clearContents()
        if let url = payload.url {
            NSPasteboard.general.setString(url, forType: .string)
        } else if let file = payload.fileURL {
            NSPasteboard.general.writeObjects([file as NSURL])
        }
    }

    private static func open(_ payload: ResultNotificationPayload) {
        if let url = payload.url.flatMap(URL.init(string:)) {
            NSWorkspace.shared.open(url)
        } else if let file = payload.fileURL, FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.open(file)
        }
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.actionIdentifier
        let payload = ResultNotificationPayload(userInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            Self.handle(action: identifier, payload: payload)
        }
    }
}

@MainActor
enum MaintenanceNotifications {
    static func post(title: String, body: String, category: String?, fallbackSymbol: String) async {
        guard !RuntimeEnvironment.isRunningTests else { return }
        if await ResultNotifier.shared.canPost() {
            await ResultNotifier.shared.postMessage(title: title, body: body, category: category)
        } else {
            ToastController.showMessage(title: title, message: body, symbol: fallbackSymbol, tint: .orange)
        }
    }
}

@MainActor
enum ResultPresenter {
    static func present(_ model: ToastModel) async {
        let presentation = Defaults[.resultPresentation]
        let notifies = presentation.postsNotification && model.fileURL != nil
        let canNotify = notifies ? await ResultNotifier.shared.canPost() : false
        guard canNotify else {
            await ToastController.show(model: model)
            return
        }
        if presentation.showsToast {
            Task { @MainActor in
                await model.waitUntilSettled()
                await postNotification(for: model)
            }
            await ToastController.show(model: model)
        } else {
            await model.waitUntilSettled()
            await postNotification(for: model)
        }
    }

    static func postNotification(for model: ToastModel) async {
        let payload = ResultNotificationPayload(url: model.historyItem?.fileUrl, path: model.fileURL?.path)
        let body: String =
            switch model.uploadState {
            case .failed: "Upload failed".localized()
            default: model.historyItem?.fileUrl ?? (Defaults[.saveToDisk] ? "Saved to disk".localized() : "Captured".localized())
            }
        await ResultNotifier.shared.post(title: model.fileName, body: body, payload: payload, thumbnail: model.thumbnail)
    }
}
