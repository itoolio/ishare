import Defaults
import SwiftUI
import UniformTypeIdentifiers

extension UploaderSettingsView {
    func save(_ uploader: CustomUploader) {
        UploaderStore.save(uploader)
    }

    func activate(_ uploader: CustomUploader) {
        activeCustomUploader = uploader.id
        uploadType = .CUSTOM
        uploadDestination = .custom(uploader.id)
    }

    func delete(_ uploader: CustomUploader) {
        forgetLocalState(of: uploader.id)
        UploaderStore.delete(uploader)
        Defaults[.additionalUploadDestinations].removeAll { $0 == .custom(uploader.id) }
        if uploader.id == activeCustomUploader {
            activeCustomUploader = nil
            uploadType = .IMGUR
            uploadDestination = .builtIn(.IMGUR)
        }
    }

    private func forgetLocalState(of id: UUID) {
        LinkOptionsResolver.forget(id)
        LocalFolderAccess.setBookmark(nil, for: id)
    }

    func clearAllUploaders() {
        CustomUploader.allCases.forEach { forgetLocalState(of: $0.id) }
        UploaderStore.deleteAll()
        Defaults[.additionalUploadDestinations].removeAll { $0 != .builtIn(.IMGUR) }
        activeCustomUploader = nil
        uploadType = .IMGUR
        uploadDestination = .builtIn(.IMGUR)
    }

    func export(_ uploader: CustomUploader) {
        let includeSecret = includesSecret(for: uploader)
        let exported = UploaderSecrets.exporting(S3SecretStore.exporting(uploader, includeSecret: includeSecret), includeSecrets: includeSecret)
        guard let data = try? exported.toJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iscu") ?? .json]
        panel.nameFieldStringValue = "\(uploader.name).iscu"
        Task { @MainActor in
            if await panel.beginAsyncModal() == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }

    private func includesSecret(for uploader: CustomUploader) -> Bool {
        guard uploader.kind == .s3 || UploaderSecrets.hasExportableSecrets(uploader) else { return false }
        let alert = NSAlert()
        alert.messageText = uploader.kind == .s3 ? "Include the secret access key?".localized() : "Include the password, key or token?".localized()
        alert.informativeText = "Anyone with the exported file can use this key.".localized()
        alert.addButton(withTitle: "Leave Out".localized())
        alert.addButton(withTitle: "Include".localized())
        return alert.runModal() == .alertSecondButtonReturn
    }
}
