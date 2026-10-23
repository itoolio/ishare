import Foundation

public enum RequestBodyType: String, Codable, CaseIterable, Sendable {
    case multipartFormData = "multipartformdata"
    case binary

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "multipartformdata", "multipart", "multipart/form-data", "formdata":
            self = .multipartFormData
        case "binary", "raw":
            self = .binary
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid request body type: \(rawValue)")
        }
    }
}

public enum DeleteRequestType: String, Codable, CaseIterable, Sendable {
    case get = "GET"
    case delete = "DELETE"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue.uppercased() {
        case "GET":
            self = .get
        case "DELETE":
            self = .delete
        default:
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid delete request type: \(rawValue)"
            )
        }
    }
}

public enum UploadRequestMethod: String, Codable, CaseIterable, Sendable {
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let method = UploadRequestMethod(rawValue: rawValue.uppercased()) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid request method: \(rawValue)")
        }
        self = method
    }
}

public enum UploaderKind: String, Codable, CaseIterable, Sendable {
    case custom
    case s3
    case webdav
    case sftp
    case dropbox
    case googleDrive = "googledrive"
    case oneDrive = "onedrive"
    case github
    case folder
    case photos

    static let aliases: [String: UploaderKind] = [
        "google-drive": .googleDrive, "google_drive": .googleDrive, "gdrive": .googleDrive,
        "one-drive": .oneDrive, "one_drive": .oneDrive, "http": .custom,
    ]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        guard let kind = UploaderKind(rawValue: rawValue) ?? Self.aliases[rawValue] else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid uploader type: \(rawValue)")
        }
        self = kind
    }

    public var isLocal: Bool {
        self == .folder || self == .photos
    }

    public var cloudProvider: CloudProvider? {
        switch self {
        case .dropbox: .dropbox
        case .googleDrive: .googleDrive
        case .oneDrive: .oneDrive
        default: nil
        }
    }

    public var symbolName: String {
        switch self {
        case .custom: "server.rack"
        case .s3: "externaldrive.connected.to.line.below"
        case .webdav: "network"
        case .sftp: "terminal"
        case .dropbox: "shippingbox"
        case .googleDrive: "triangle"
        case .oneDrive: "cloud"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .folder: "folder"
        case .photos: "photo.on.rectangle"
        }
    }

    public var titleKey: String {
        switch self {
        case .custom: "Custom HTTP uploader"
        case .s3: "S3-compatible storage"
        case .webdav: "WebDAV"
        case .sftp: "SFTP"
        case .dropbox: "Dropbox"
        case .googleDrive: "Google Drive"
        case .oneDrive: "OneDrive"
        case .github: "GitHub"
        case .folder: "Folder"
        case .photos: "Photos"
        }
    }
}

public struct CustomUploader: Codable, Hashable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public let name: String
    public let requestURL: String
    public let headers: [String: String]?
    public let formData: [String: String]?
    public let fileFormName: String?
    public let requestBodyType: RequestBodyType?
    public let responseURL: String
    public let deletionURL: String?
    public let deleteRequestType: DeleteRequestType?
    public let uploaderType: UploaderKind?
    public var s3: S3Configuration?
    public var requestMethod: UploadRequestMethod?
    public var modifiedAt: Date?
    public var linkOptions: LinkOptionsSpec?
    public var folder: FolderDestination?
    public var photos: PhotosDestination?
    public var webdav: WebDAVConfiguration?
    public var sftp: SFTPConfiguration?
    public var cloud: CloudStorageConfiguration?
    public var github: GitHubConfiguration?
    public var imageOptimization: ImageOptimizationOverride?

    public init(
        id: UUID = UUID(), name: String, requestURL: String, headers: [String: String]?,
        formData: [String: String]?, fileFormName: String?, requestBodyType: RequestBodyType? = nil,
        responseURL: String, deletionURL: String? = nil, deleteRequestType: DeleteRequestType? = nil,
        uploaderType: UploaderKind? = nil, s3: S3Configuration? = nil, requestMethod: UploadRequestMethod? = nil,
        modifiedAt: Date? = nil, linkOptions: LinkOptionsSpec? = nil, folder: FolderDestination? = nil,
        photos: PhotosDestination? = nil, webdav: WebDAVConfiguration? = nil, sftp: SFTPConfiguration? = nil,
        cloud: CloudStorageConfiguration? = nil, github: GitHubConfiguration? = nil,
        imageOptimization: ImageOptimizationOverride? = nil
    ) {
        self.id = id
        self.name = name
        self.requestURL = requestURL
        self.headers = headers
        self.formData = formData
        self.fileFormName = fileFormName
        self.requestBodyType = requestBodyType
        self.responseURL = responseURL
        self.deletionURL = deletionURL
        self.deleteRequestType = deleteRequestType
        self.uploaderType = uploaderType
        self.s3 = s3
        self.requestMethod = requestMethod
        self.modifiedAt = modifiedAt
        self.linkOptions = linkOptions
        self.folder = folder
        self.photos = photos
        self.webdav = webdav
        self.sftp = sftp
        self.cloud = cloud
        self.github = github
        self.imageOptimization = imageOptimization
    }

    public static func folder(id: UUID = UUID(), name: String, destination: FolderDestination) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: "", headers: nil, formData: nil, fileFormName: nil,
            responseURL: "", uploaderType: .folder, folder: destination
        )
    }

    public static func photos(id: UUID = UUID(), name: String, destination: PhotosDestination) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: "", headers: nil, formData: nil, fileFormName: nil,
            responseURL: "", uploaderType: .photos, photos: destination
        )
    }

    public static func s3(id: UUID = UUID(), name: String, configuration: S3Configuration) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: "", headers: nil, formData: nil, fileFormName: nil,
            responseURL: "", uploaderType: .s3, s3: configuration
        )
    }

    public static func remote(id: UUID = UUID(), name: String, kind: UploaderKind) -> CustomUploader {
        CustomUploader(id: id, name: name, requestURL: "", headers: nil, formData: nil, fileFormName: nil, responseURL: "", uploaderType: kind)
    }

    public static func webdav(id: UUID = UUID(), name: String, configuration: WebDAVConfiguration) -> CustomUploader {
        var uploader = remote(id: id, name: name, kind: .webdav)
        uploader.webdav = configuration
        return uploader
    }

    public static func sftp(id: UUID = UUID(), name: String, configuration: SFTPConfiguration) -> CustomUploader {
        var uploader = remote(id: id, name: name, kind: .sftp)
        uploader.sftp = configuration
        return uploader
    }

    public static func cloud(id: UUID = UUID(), name: String, provider: CloudProvider, configuration: CloudStorageConfiguration) -> CustomUploader {
        var uploader = remote(id: id, name: name, kind: provider.kind)
        uploader.cloud = configuration
        return uploader
    }

    public static func github(id: UUID = UUID(), name: String, configuration: GitHubConfiguration) -> CustomUploader {
        var uploader = remote(id: id, name: name, kind: .github)
        uploader.github = configuration
        return uploader
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case requestURL = "requesturl"
        case headers
        case formData = "formdata"
        case fileFormName = "fileformname"
        case requestBodyType = "requestbodytype"
        case responseURL = "responseurl"
        case deletionURL = "deletionurl"
        case deleteRequestType = "deleterequesttype"
        case uploaderType = "uploadertype"
        case s3
        case requestMethod = "requestmethod"
        case modifiedAt = "modifiedat"
        case linkOptions = "linkoptions"
        case folder
        case photos
        case webdav
        case sftp
        case cloud
        case github
        case imageOptimization = "imageoptimization"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try container.decodeDynamicIfPresent(UUID.self, forKey: .key(named: "id")) ?? UUID()
        name = try container.decodeDynamic(String.self, forKey: .key(named: "name"))
        s3 = try container.decodeDynamicIfPresent(S3Configuration.self, forKey: .key(named: "s3"))
        folder = try container.decodeDynamicIfPresent(FolderDestination.self, forKey: .key(named: "folder"))
        photos = try container.decodeDynamicIfPresent(PhotosDestination.self, forKey: .key(named: "photos"))
        webdav = try container.decodeDynamicIfPresent(WebDAVConfiguration.self, forKey: .key(named: "webdav"))
        sftp = try container.decodeDynamicIfPresent(SFTPConfiguration.self, forKey: .key(named: "sftp"))
        cloud = try container.decodeDynamicIfPresent(CloudStorageConfiguration.self, forKey: .key(named: "cloud"))
        github = try container.decodeDynamicIfPresent(GitHubConfiguration.self, forKey: .key(named: "github"))
        imageOptimization = try container.decodeDynamicIfPresent(ImageOptimizationOverride.self, forKey: .key(named: "imageoptimization"))
        linkOptions = try container.decodeDynamicIfPresent(LinkOptionsSpec.self, forKey: .key(named: "linkoptions"))
        let declaredKind = try container.decodeDynamicIfPresent(UploaderKind.self, forKey: .key(named: "uploadertype"))
        uploaderType = declaredKind ?? Self.inferredKind(s3: s3, folder: folder, photos: photos)
            ?? Self.inferredRemoteKind(webdav: webdav, sftp: sftp, github: github)
        let needsRequest = uploaderType == nil || uploaderType == .custom
        if !needsRequest {
            requestURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "requesturl")) ?? ""
            responseURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "responseurl")) ?? ""
        } else {
            requestURL = try container.decodeDynamic(String.self, forKey: .key(named: "requesturl"))
            responseURL = try container.decodeDynamic(String.self, forKey: .key(named: "responseurl"))
        }
        headers = try container.decodeDynamicIfPresent([String: String].self, forKey: .key(named: "headers"))
        formData = try container.decodeDynamicIfPresent([String: String].self, forKey: .key(named: "formdata"))
        fileFormName = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "fileformname"))
        requestBodyType = try container.decodeDynamicIfPresent(RequestBodyType.self, forKey: .key(named: "requestbodytype"))
        deletionURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "deletionurl"))
        deleteRequestType = try container.decodeDynamicIfPresent(DeleteRequestType.self, forKey: .key(named: "deleterequesttype"))
        requestMethod = try container.decodeDynamicIfPresent(UploadRequestMethod.self, forKey: .key(named: "requestmethod"))
        modifiedAt = try container.decodeDynamicIfPresent(Date.self, forKey: .key(named: "modifiedat"))
    }

    public var kind: UploaderKind { uploaderType ?? .custom }

    private static func inferredKind(s3: S3Configuration?, folder: FolderDestination?, photos: PhotosDestination?) -> UploaderKind? {
        if s3 != nil { return .s3 }
        if folder != nil { return .folder }
        if photos != nil { return .photos }
        return nil
    }

    private static func inferredRemoteKind(webdav: WebDAVConfiguration?, sftp: SFTPConfiguration?, github: GitHubConfiguration?) -> UploaderKind? {
        if webdav != nil { return .webdav }
        if sftp != nil { return .sftp }
        if github != nil { return .github }
        return nil
    }

    public var isLocalOnly: Bool {
        kind == .folder || kind == .photos
    }

    public static func == (lhs: CustomUploader, rhs: CustomUploader) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func fromJSON(_ json: Data) throws -> CustomUploader {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(CustomUploader.self, from: json)
    }

    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func isValid() -> Bool {
        UploaderValidator.issues(for: self).isEmpty
    }

    public func withID(_ newID: UUID) -> CustomUploader {
        var copy = self
        copy.id = newID
        return copy
    }

    public func renamed(_ newName: String) -> CustomUploader {
        var copy = CustomUploader(
            id: id, name: newName, requestURL: requestURL, headers: headers, formData: formData, fileFormName: fileFormName,
            requestBodyType: requestBodyType, responseURL: responseURL, deletionURL: deletionURL,
            deleteRequestType: deleteRequestType, uploaderType: uploaderType, s3: s3, requestMethod: requestMethod,
            modifiedAt: modifiedAt, linkOptions: linkOptions, folder: folder, photos: photos
        )
        copy.webdav = webdav
        copy.sftp = sftp
        copy.cloud = cloud
        copy.github = github
        copy.imageOptimization = imageOptimization
        return copy
    }

    public func touched(at date: Date = .init()) -> CustomUploader {
        var copy = self
        copy.modifiedAt = date
        return copy
    }

    public func hasSameContent(as other: CustomUploader) -> Bool {
        var lhs = self
        var rhs = other
        lhs.modifiedAt = nil
        rhs.modifiedAt = nil
        return (try? lhs.toJSON()) == (try? rhs.toJSON())
    }
}

struct DynamicCodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
    }

    public init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    public static func key(named name: String) -> DynamicCodingKey {
        DynamicCodingKey(stringValue: name)!
    }
}

extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decodeDynamic<T: Decodable>(_: T.Type, forKey key: DynamicCodingKey) throws -> T {
        let keyString = key.stringValue.lowercased()
        guard let dynamicKey = allKeys.first(where: { $0.stringValue.lowercased() == keyString }) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "No value associated with key \(keyString)")
            )
        }
        return try decode(T.self, forKey: dynamicKey)
    }

    func decodeDynamicIfPresent<T: Decodable>(_: T.Type, forKey key: DynamicCodingKey) throws -> T? {
        let keyString = key.stringValue.lowercased()
        guard let dynamicKey = allKeys.first(where: { $0.stringValue.lowercased() == keyString }) else {
            return nil
        }
        return try decodeIfPresent(T.self, forKey: dynamicKey)
    }
}
