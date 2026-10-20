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

    static let malformedTemplateFormat = "The %@ template has unbalanced {{ }} placeholders"
    static let missingS3FieldFormat = "The S3 %@ is required"

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
        }
    }

    var argument: String? {
        switch self {
        case let .malformedTemplate(field), let .missingS3Field(field): field
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
        }
        return issues
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
        return issues
    }
}
