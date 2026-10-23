import Foundation

enum UploaderIssue: Equatable, Sendable {
    case missingName
    case invalidRequestURL
    case missingResponseURL
    case malformedTemplate(field: String)
    case emptyFileFormName
    case missingS3Configuration
    case invalidS3Endpoint
    case missingS3Field(String)
    case invalidPresignedExpiry
    case emptyLinkOptions
    case missingLinkOptionField(String)
    case linkOptionTemplateWithoutValue(String)
    case linkOptionFormWithBinaryBody(String)
    case missingFolder
    case invalidFolderPublicURL
    case missingRemoteConfiguration
    case invalidWebDAVURL
    case missingRemoteField(String)
    case invalidPort
    case missingSFTPCredentials
    case invalidPublicURLTemplate
    case invalidGitHubRepository
    case missingCloudClientID

    static let malformedTemplateFormat = "The %@ template has unbalanced {{ }} placeholders"
    static let missingS3FieldFormat = "The S3 %@ is required"
    static let missingLinkOptionFieldFormat = "The %@ link option needs a field name"
    static let linkOptionTemplateWithoutValueFormat = "The %@ link option template must contain {{value}}"
    static let linkOptionFormWithBinaryBodyFormat = "The %@ link option can't be sent as form data with a binary body"
    static let missingRemoteFieldFormat = "The %@ is required"

    var messageKey: String {
        switch self {
        case .missingName: "The uploader needs a name"
        case .invalidRequestURL: "The request URL must be a valid http or https URL"
        case .missingResponseURL: "The response URL template is required"
        case .malformedTemplate: Self.malformedTemplateFormat
        case .emptyFileFormName: "The file form name cannot be empty"
        case .missingS3Configuration: "S3 uploaders need an S3 configuration"
        case .invalidS3Endpoint: "The S3 endpoint must be a valid URL"
        case .missingS3Field: Self.missingS3FieldFormat
        case .invalidPresignedExpiry: "Link expiry must be between 1 second and 7 days"
        case .emptyLinkOptions: "Link options need a password or expiry field"
        case .missingLinkOptionField: Self.missingLinkOptionFieldFormat
        case .linkOptionTemplateWithoutValue: Self.linkOptionTemplateWithoutValueFormat
        case .linkOptionFormWithBinaryBody: Self.linkOptionFormWithBinaryBodyFormat
        case .missingFolder: "Choose a folder to save uploads to"
        case .invalidFolderPublicURL: "The public URL must start with http:// or https://"
        case .missingRemoteConfiguration: "This uploader is missing its connection settings"
        case .invalidWebDAVURL: "The WebDAV URL must be a valid http or https URL"
        case .missingRemoteField: Self.missingRemoteFieldFormat
        case .invalidPort: "The port must be between 1 and 65535"
        case .missingSFTPCredentials: "Enter a password or a private key for the SFTP server"
        case .invalidPublicURLTemplate: "The public URL must start with http:// or https://"
        case .invalidGitHubRepository: "Enter the repository as owner/name"
        case .missingCloudClientID: "Paste the client ID of your own app to use this provider"
        }
    }

    var argument: String? {
        switch self {
        case let .malformedTemplate(field), let .missingS3Field(field), let .missingLinkOptionField(field),
             let .linkOptionTemplateWithoutValue(field), let .linkOptionFormWithBinaryBody(field): field
        default: nil
        }
    }

    var message: String {
        argument.map { String(format: messageKey, $0) } ?? messageKey
    }

    @MainActor var localizedMessage: String {
        argument.map { String(format: messageKey.localized(), $0.localized()) } ?? messageKey.localized()
    }
}

enum UploaderValidator {
    static func issues(for uploader: CustomUploader) -> [UploaderIssue] {
        var issues: [UploaderIssue] = []
        if uploader.name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingName)
        }
        switch uploader.kind {
        case .custom:
            issues += customIssues(for: uploader)
        case .s3:
            issues += s3Issues(for: uploader.s3)
        case .folder:
            issues += folderIssues(for: uploader.folder)
        case .photos:
            break
        case .webdav:
            issues += webdavIssues(for: uploader.webdav)
        case .sftp:
            issues += sftpIssues(for: uploader.sftp)
        case .github:
            issues += githubIssues(for: uploader.github)
        case .dropbox, .googleDrive, .oneDrive:
            issues += cloudIssues(for: uploader.cloud, provider: uploader.kind.cloudProvider)
        }
        return issues
    }

    static func pathTemplateIssues(_ template: String?) -> [UploaderIssue] {
        guard let template, !isWellFormedTemplate(template) else { return [] }
        return [.malformedTemplate(field: "path")]
    }

    static func publicURLIssues(_ template: String?) -> [UploaderIssue] {
        guard let template = template?.trimmingCharacters(in: .whitespaces), !template.isEmpty else { return [] }
        guard isWellFormedTemplate(template) else { return [.malformedTemplate(field: "public URL")] }
        let lowered = template.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://") ? [] : [.invalidPublicURLTemplate]
    }

    private static func webdavIssues(for configuration: WebDAVConfiguration?) -> [UploaderIssue] {
        guard let configuration else { return [.missingRemoteConfiguration] }
        var issues: [UploaderIssue] = []
        if configuration.baseURL == nil {
            issues.append(.invalidWebDAVURL)
        }
        return issues + pathTemplateIssues(configuration.pathTemplate) + publicURLIssues(configuration.publicURL)
    }

    private static func sftpIssues(for configuration: SFTPConfiguration?) -> [UploaderIssue] {
        guard let configuration else { return [.missingRemoteConfiguration] }
        var issues: [UploaderIssue] = []
        if configuration.trimmedHost.isEmpty {
            issues.append(.missingRemoteField("host"))
        }
        if configuration.username.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingRemoteField("username"))
        }
        if let port = configuration.port, !(1 ... 65535).contains(port) {
            issues.append(.invalidPort)
        }
        if !configuration.usesPrivateKey, (configuration.password ?? "").isEmpty {
            issues.append(.missingSFTPCredentials)
        }
        return issues + pathTemplateIssues(configuration.pathTemplate) + publicURLIssues(configuration.publicURL)
    }

    private static func githubIssues(for configuration: GitHubConfiguration?) -> [UploaderIssue] {
        guard let configuration else { return [.missingRemoteConfiguration] }
        var issues: [UploaderIssue] = []
        if configuration.ownerAndName == nil {
            issues.append(.invalidGitHubRepository)
        }
        if (configuration.token ?? "").isEmpty {
            issues.append(.missingRemoteField("access token"))
        }
        return issues + pathTemplateIssues(configuration.pathTemplate)
    }

    private static func cloudIssues(for configuration: CloudStorageConfiguration?, provider: CloudProvider?) -> [UploaderIssue] {
        var issues: [UploaderIssue] = []
        let customClientID = configuration?.clientID?.trimmingCharacters(in: .whitespaces) ?? ""
        if let provider, !provider.hasBuiltInClientID, customClientID.isEmpty {
            issues.append(.missingCloudClientID)
        }
        return issues + pathTemplateIssues(configuration?.pathTemplate)
    }

    static func isWellFormedTemplate(_ template: String) -> Bool {
        var depth = 0
        var index = template.startIndex
        while index < template.endIndex {
            let rest = template[index...]
            if rest.hasPrefix("{{") {
                guard depth == 0 else { return false }
                depth = 1
                index = template.index(index, offsetBy: 2)
                continue
            }
            if rest.hasPrefix("}}") {
                guard depth == 1 else { return false }
                depth = 0
                index = template.index(index, offsetBy: 2)
                continue
            }
            index = template.index(after: index)
        }
        return depth == 0
    }

    static func isHTTPURL(_ string: String) -> Bool {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return false }
        return true
    }

    private static func customIssues(for uploader: CustomUploader) -> [UploaderIssue] {
        var issues: [UploaderIssue] = []
        if !isHTTPURL(uploader.requestURL) {
            issues.append(.invalidRequestURL)
        }
        if uploader.responseURL.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingResponseURL)
        } else if !isWellFormedTemplate(uploader.responseURL) {
            issues.append(.malformedTemplate(field: "response URL"))
        }
        if let deletionURL = uploader.deletionURL, !isWellFormedTemplate(deletionURL) {
            issues.append(.malformedTemplate(field: "deletion URL"))
        }
        if let fileFormName = uploader.fileFormName, fileFormName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.emptyFileFormName)
        }
        if let linkOptions = uploader.linkOptions {
            issues += linkOptionIssues(for: linkOptions, bodyType: uploader.requestBodyType ?? .multipartFormData)
        }
        return issues
    }

    static func linkOptionIssues(for spec: LinkOptionsSpec, bodyType: RequestBodyType) -> [UploaderIssue] {
        guard !spec.isEmpty else { return [.emptyLinkOptions] }
        var issues: [UploaderIssue] = []
        if let password = spec.password {
            issues += linkFieldIssues(name: "password", field: password.field, location: password.location, template: password.template, bodyType: bodyType)
        }
        if let expiry = spec.expiry {
            issues += linkFieldIssues(name: "expiry", field: expiry.field, location: expiry.location, template: expiry.template, bodyType: bodyType)
        }
        return issues
    }

    private static func linkFieldIssues(
        name: String, field: String, location: LinkOptionLocation, template: String?, bodyType: RequestBodyType
    ) -> [UploaderIssue] {
        var issues: [UploaderIssue] = []
        if field.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingLinkOptionField(name))
        }
        if location == .form, bodyType == .binary {
            issues.append(.linkOptionFormWithBinaryBody(name))
        }
        if let template, !template.trimmingCharacters(in: .whitespaces).isEmpty {
            if !isWellFormedTemplate(template) {
                issues.append(.malformedTemplate(field: "\(name) link option"))
            } else if !ResponseTemplate.placeholders(in: template).contains(where: {
                $0.trimmingCharacters(in: .whitespaces).lowercased() == LinkOptionsEncoder.valuePlaceholder
            }) {
                issues.append(.linkOptionTemplateWithoutValue(name))
            }
        }
        return issues
    }

    private static func folderIssues(for destination: FolderDestination?) -> [UploaderIssue] {
        guard let destination else { return [.missingFolder] }
        var issues: [UploaderIssue] = []
        if destination.folderURL == nil {
            issues.append(.missingFolder)
        }
        if let template = destination.subfolderTemplate, !isWellFormedTemplate(template) {
            issues.append(.malformedTemplate(field: "subfolder"))
        }
        if let template = destination.publicURL?.trimmingCharacters(in: .whitespaces), !template.isEmpty {
            if !isWellFormedTemplate(template) {
                issues.append(.malformedTemplate(field: "public URL"))
            } else if !(template.lowercased().hasPrefix("http://") || template.lowercased().hasPrefix("https://")) {
                issues.append(.invalidFolderPublicURL)
            }
        }
        return issues
    }

    private static func s3Issues(for configuration: S3Configuration?) -> [UploaderIssue] {
        guard let configuration else { return [.missingS3Configuration] }
        var issues: [UploaderIssue] = []
        if configuration.endpointURL == nil {
            issues.append(.invalidS3Endpoint)
        }
        let required: [(String, String)] = [
            ("bucket", configuration.bucket),
            ("region", configuration.region),
            ("access key ID", configuration.accessKeyId),
            ("secret access key", configuration.secretAccessKey),
        ]
        for (field, value) in required where value.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingS3Field(field))
        }
        if let template = configuration.keyTemplate, !isWellFormedTemplate(template) {
            issues.append(.malformedTemplate(field: "key"))
        }
        if let template = configuration.publicURL, !isWellFormedTemplate(template) {
            issues.append(.malformedTemplate(field: "public URL"))
        }
        if let expiry = configuration.presignedExpiry, !S3Configuration.presignedExpiryRange.contains(expiry) {
            issues.append(.invalidPresignedExpiry)
        }
        return issues
    }
}
