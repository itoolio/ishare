import ishareCore
import SwiftUI

extension UploaderEditorView {
    var issues: [UploaderIssue] {
        UploaderValidator.issues(for: build())
    }

    func save() {
        let uploader = build()
        if uploader.kind == .custom, uploader.linkOptions != nil {
            LinkOptionsResolver.setPreferences(linkPreferences, for: uploader.id)
            LinkPasswordStore.setPassword(linkPreferences.usesPassword ? defaultLinkPassword : nil, for: uploader.id)
        } else {
            LinkOptionsResolver.forget(uploader.id)
        }
        LocalFolderAccess.setBookmark(uploader.kind == .folder ? folderDraft.bookmark : nil, for: uploader.id)
        clearRemovedSecrets(of: uploader)
        if uploader.kind.cloudProvider == nil {
            try? OAuthTokenStore.save(nil, for: uploader.id)
        }
        onSave(uploader)
    }

    private func clearRemovedSecrets(of uploader: CustomUploader) {
        let values: [(UploaderSecretField, String?)] = [
            (.password, uploader.webdav?.password ?? uploader.sftp?.password),
            (.privateKey, uploader.sftp?.privateKey),
            (.passphrase, uploader.sftp?.passphrase),
            (.accessToken, uploader.github?.token),
        ]
        for (field, value) in values where value == nil {
            try? UploaderSecrets.write(nil, field, for: uploader.id)
        }
    }

    func load() {
        switch target {
        case let .new(newKind):
            kind = newKind
            name = newKind.isLocal || newKind.cloudProvider != nil ? newKind.titleKey.localized() : ""
        case .iCloudDrive:
            kind = .folder
            name = "iCloud Drive"
            suggestsICloudDrive = true
        case let .edit(uploader):
            id = uploader.id
            kind = uploader.kind
            name = uploader.name
            requestURL = uploader.requestURL
            responseURL = uploader.responseURL
            deletionURL = uploader.deletionURL ?? ""
            fileFormName = uploader.fileFormName ?? ""
            bodyType = uploader.requestBodyType ?? .multipartFormData
            deleteMethod = uploader.deleteRequestType ?? .get
            headers = (uploader.headers ?? [:]).sorted { $0.key < $1.key }.map { CustomEntryModel(key: $0.key, value: $0.value) }
            formData = (uploader.formData ?? [:]).sorted { $0.key < $1.key }.map { CustomEntryModel(key: $0.key, value: $0.value) }
            if let s3 = uploader.s3 {
                endpoint = s3.endpoint
                region = s3.region
                bucket = s3.bucket
                accessKeyId = s3.accessKeyId
                secretAccessKey = S3SecretStore.secret(for: uploader) ?? ""
                pathStyle = s3.usesPathStyle
                keyTemplate = s3.keyTemplate ?? ""
                acl = s3.acl ?? ""
                publicURL = s3.publicURL ?? ""
                expiringLinks = s3.presignedExpiry != nil
                presignedExpiry = s3.presignedExpiry ?? presignedExpiry
            }
            requestMethod = uploader.requestMethod ?? .post
            linkDraft = LinkOptionsDraft(spec: uploader.linkOptions)
            linkPreferences = LinkOptionsResolver.preferences(for: uploader.id)
            defaultLinkPassword = LinkPasswordStore.password(for: uploader.id) ?? ""
            folderDraft = FolderDraft(destination: uploader.folder, bookmark: LocalFolderAccess.bookmark(for: uploader.id))
            photosDraft = PhotosDraft(destination: uploader.photos)
            webdavDraft = WebDAVDraft(uploader: uploader)
            sftpDraft = SFTPDraft(uploader: uploader)
            cloudDraft = CloudDraft(uploader: uploader)
            githubDraft = GitHubDraft(uploader: uploader)
            optimizationOverride = uploader.imageOptimization ?? ImageOptimizationOverride()
            loadMaintenance(from: uploader)
        }
    }

    private func dictionary(_ entries: [CustomEntryModel]) -> [String: String]? {
        let pairs = entries.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !pairs.isEmpty else { return nil }
        return Dictionary(pairs.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    func build() -> CustomUploader {
        var uploader = buildDefinition()
        uploader.imageOptimization = kind == .photos || optimizationOverride.isEmpty ? nil : optimizationOverride
        applyMaintenance(to: &uploader)
        return uploader
    }

    private func buildDefinition() -> CustomUploader {
        switch kind {
        case .webdav:
            return .webdav(id: id, name: name, configuration: webdavDraft.configuration)
        case .sftp:
            return .sftp(id: id, name: name, configuration: sftpDraft.configuration)
        case .dropbox, .googleDrive, .oneDrive:
            return .cloud(id: id, name: name, provider: kind.cloudProvider ?? .dropbox, configuration: cloudDraft.configuration)
        case .github:
            return .github(id: id, name: name, configuration: githubDraft.configuration)
        case .s3:
            return .s3(
                id: id, name: name,
                configuration: S3Configuration(
                    endpoint: endpoint, region: region, bucket: bucket, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey,
                    pathStyle: pathStyle, keyTemplate: nonEmpty(keyTemplate), acl: nonEmpty(acl), publicURL: nonEmpty(publicURL),
                    presignedExpiry: expiringLinks ? presignedExpiry : nil
                ))
        case .folder:
            return .folder(id: id, name: name, destination: folderDraft.destination)
        case .photos:
            return .photos(id: id, name: name, destination: photosDraft.destination)
        case .custom:
            return CustomUploader(
                id: id, name: name, requestURL: requestURL.trimmingCharacters(in: .whitespaces),
                headers: dictionary(headers), formData: bodyType == .multipartFormData ? dictionary(formData) : nil,
                fileFormName: bodyType == .multipartFormData ? nonEmpty(fileFormName) : nil,
                requestBodyType: bodyType, responseURL: responseURL.trimmingCharacters(in: .whitespaces),
                deletionURL: nonEmpty(deletionURL), deleteRequestType: nonEmpty(deletionURL) == nil ? nil : deleteMethod,
                requestMethod: requestMethod == .post ? nil : requestMethod, linkOptions: linkDraft.spec
            )
        }
    }
}
