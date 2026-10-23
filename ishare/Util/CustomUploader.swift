import Defaults
import Foundation

enum RequestBodyType: String, Codable, CaseIterable, Sendable {
    case multipartFormData = "multipartformdata"
    case binary

    init(from decoder: any Decoder) throws {
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

enum DeleteRequestType: String, Codable, CaseIterable, Sendable {
    case get = "GET"
    case delete = "DELETE"

    init(from decoder: any Decoder) throws {
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

enum UploadRequestMethod: String, Codable, CaseIterable, Sendable {
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let method = UploadRequestMethod(rawValue: rawValue.uppercased()) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid request method: \(rawValue)")
        }
        self = method
    }
}

enum UploaderKind: String, Codable, CaseIterable, Sendable {
    case custom
    case s3
    case folder
    case photos

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        guard let kind = UploaderKind(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid uploader type: \(rawValue)")
        }
        self = kind
    }

    var isLocal: Bool {
        self == .folder || self == .photos
    }

    var symbolName: String {
        switch self {
        case .custom: "server.rack"
        case .s3: "externaldrive.connected.to.line.below"
        case .folder: "folder"
        case .photos: "photo.on.rectangle"
        }
    }

    var titleKey: String {
        switch self {
        case .custom: "Custom HTTP uploader"
        case .s3: "S3-compatible storage"
        case .folder: "Folder"
        case .photos: "Photos"
        }
    }
}

struct CustomUploader: Codable, Hashable, Equatable, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    var id: UUID
    let name: String
    let requestURL: String
    let headers: [String: String]?
    let formData: [String: String]?
    let fileFormName: String?
    let requestBodyType: RequestBodyType?
    let responseURL: String
    let deletionURL: String?
    let deleteRequestType: DeleteRequestType?
    let uploaderType: UploaderKind?
    var s3: S3Configuration?
    var requestMethod: UploadRequestMethod?
    var modifiedAt: Date?
    var linkOptions: LinkOptionsSpec?
    var folder: FolderDestination?
    var photos: PhotosDestination?

    init(
        id: UUID = UUID(), name: String, requestURL: String, headers: [String: String]?,
        formData: [String: String]?, fileFormName: String?, requestBodyType: RequestBodyType? = nil,
        responseURL: String, deletionURL: String? = nil, deleteRequestType: DeleteRequestType? = nil,
        uploaderType: UploaderKind? = nil, s3: S3Configuration? = nil, requestMethod: UploadRequestMethod? = nil,
        modifiedAt: Date? = nil, linkOptions: LinkOptionsSpec? = nil, folder: FolderDestination? = nil,
        photos: PhotosDestination? = nil
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
    }

    static func folder(id: UUID = UUID(), name: String, destination: FolderDestination) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: "", headers: nil, formData: nil, fileFormName: nil,
            responseURL: "", uploaderType: .folder, folder: destination
        )
    }

    static func photos(id: UUID = UUID(), name: String, destination: PhotosDestination) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: "", headers: nil, formData: nil, fileFormName: nil,
            responseURL: "", uploaderType: .photos, photos: destination
        )
    }

    static func s3(id: UUID = UUID(), name: String, configuration: S3Configuration) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: "", headers: nil, formData: nil, fileFormName: nil,
            responseURL: "", uploaderType: .s3, s3: configuration
        )
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
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try container.decodeDynamicIfPresent(UUID.self, forKey: .key(named: "id")) ?? UUID()
        name = try container.decodeDynamic(String.self, forKey: .key(named: "name"))
        s3 = try container.decodeDynamicIfPresent(S3Configuration.self, forKey: .key(named: "s3"))
        folder = try container.decodeDynamicIfPresent(FolderDestination.self, forKey: .key(named: "folder"))
        photos = try container.decodeDynamicIfPresent(PhotosDestination.self, forKey: .key(named: "photos"))
        linkOptions = try container.decodeDynamicIfPresent(LinkOptionsSpec.self, forKey: .key(named: "linkoptions"))
        let declaredKind = try container.decodeDynamicIfPresent(UploaderKind.self, forKey: .key(named: "uploadertype"))
        uploaderType = declaredKind ?? Self.inferredKind(s3: s3, folder: folder, photos: photos)
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

    var kind: UploaderKind { uploaderType ?? .custom }

    private static func inferredKind(s3: S3Configuration?, folder: FolderDestination?, photos: PhotosDestination?) -> UploaderKind? {
        if s3 != nil { return .s3 }
        if folder != nil { return .folder }
        if photos != nil { return .photos }
        return nil
    }

    static var allCases: [CustomUploader] {
        Defaults[.savedCustomUploaders]?.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) ?? []
    }

    static func == (lhs: CustomUploader, rhs: CustomUploader) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func fromJSON(_ json: Data) throws -> CustomUploader {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(CustomUploader.self, from: json)
    }

    func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func isValid() -> Bool {
        UploaderValidator.issues(for: self).isEmpty
    }

    func withID(_ newID: UUID) -> CustomUploader {
        var copy = self
        copy.id = newID
        return copy
    }

    func renamed(_ newName: String) -> CustomUploader {
        CustomUploader(
            id: id, name: newName, requestURL: requestURL, headers: headers, formData: formData, fileFormName: fileFormName,
            requestBodyType: requestBodyType, responseURL: responseURL, deletionURL: deletionURL,
            deleteRequestType: deleteRequestType, uploaderType: uploaderType, s3: s3, requestMethod: requestMethod,
            modifiedAt: modifiedAt, linkOptions: linkOptions, folder: folder, photos: photos
        )
    }

    func touched(at date: Date = .init()) -> CustomUploader {
        var copy = self
        copy.modifiedAt = date
        return copy
    }

    func hasSameContent(as other: CustomUploader) -> Bool {
        var lhs = self
        var rhs = other
        lhs.modifiedAt = nil
        rhs.modifiedAt = nil
        return (try? lhs.toJSON()) == (try? rhs.toJSON())
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    static func key(named name: String) -> DynamicCodingKey {
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
