import AppKit
import BezelNotification
import Defaults
import ishareCore

@MainActor
func importIscu(_ url: URL) {
    if url.pathExtension.lowercased() == SettingsArchive.fileExtension {
        SettingsTransferFlow.importArchive(from: url)
    } else {
        importUploaderFile(url)
    }
}

@MainActor
func importUploaderFile(_ url: URL) {
    NSApp.activate(ignoringOtherApps: true)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let uploader: CustomUploader
    do {
        uploader = try UploaderFile.decode(contentsOf: url)
    } catch {
        let alert = NSAlert(error: error)
        alert.messageText = "Import Error".localized()
        alert.runModal()
        return
    }
    let alert = NSAlert()
    alert.messageText = "Import ISCU".localized()
    alert.informativeText = String(format: "Do you want to import the uploader “%@”?".localized(), uploader.name)
    alert.addButton(withTitle: "Import".localized())
    alert.addButton(withTitle: "Cancel".localized())
    guard ScreenshotMode.isActive || ProcessInfo.processInfo.arguments.contains("-ishareImportWithoutConfirmation") || alert.runModal() == .alertFirstButtonReturn else { return }
    UploaderStore.save(uploader)
    Defaults[.activeCustomUploader] = uploader.id
    Defaults[.uploadType] = .CUSTOM
    Defaults[.uploadDestination] = .custom(uploader.id)
    BezelNotification.show(messageText: String(format: "Selected %@".localized(), uploader.name), icon: ToastIcon)
}
