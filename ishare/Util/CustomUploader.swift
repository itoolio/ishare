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

enum UploaderKind: String, Codable, CaseIterable, Sendable {
    case custom
    case s3

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        guard let kind = UploaderKind(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid uploader type: \(rawValue)")
        }
        self = kind
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
    let s3: S3Configuration?

    init(
        id: UUID = UUID(), name: String, requestURL: String, headers: [String: String]?,
        formData: [String: String]?, fileFormName: String?, requestBodyType: RequestBodyType? = nil,
        responseURL: String, deletionURL: String? = nil, deleteRequestType: DeleteRequestType? = nil,
        uploaderType: UploaderKind? = nil, s3: S3Configuration? = nil
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
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try container.decodeDynamicIfPresent(UUID.self, forKey: .key(named: "id")) ?? UUID()
        name = try container.decodeDynamic(String.self, forKey: .key(named: "name"))
        s3 = try container.decodeDynamicIfPresent(S3Configuration.self, forKey: .key(named: "s3"))
        let declaredKind = try container.decodeDynamicIfPresent(UploaderKind.self, forKey: .key(named: "uploadertype"))
        uploaderType = declaredKind ?? (s3 == nil ? nil : .s3)
        let isS3 = uploaderType == .s3
        if isS3 {
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
    }

    var kind: UploaderKind { uploaderType ?? .custom }

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
