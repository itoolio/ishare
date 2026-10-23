import Foundation

public struct PhotosDestination: Codable, Hashable, Sendable {
    public static let defaultAlbumName = "ishare"

    public var albumName: String
    public var albumIdentifier: String?

    public init(albumName: String = PhotosDestination.defaultAlbumName, albumIdentifier: String? = nil) {
        self.albumName = albumName
        self.albumIdentifier = albumIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case albumName = "album"
        case albumIdentifier = "albumidentifier"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        albumName = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "album")) ?? Self.defaultAlbumName
        albumIdentifier = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "albumidentifier"))
    }

    public var target: PhotosAlbumTarget {
        let name = albumName.trimmingCharacters(in: .whitespaces)
        if let albumIdentifier, !albumIdentifier.isEmpty {
            return .existing(identifier: albumIdentifier, fallbackName: name.isEmpty ? nil : name)
        }
        if !name.isEmpty {
            return .named(name)
        }
        return .library
    }
}

public enum PhotosAlbumTarget: Equatable, Sendable {
    case library
    case named(String)
    case existing(identifier: String, fallbackName: String?)

    public var needsFullAccess: Bool {
        self != .library
    }
}
