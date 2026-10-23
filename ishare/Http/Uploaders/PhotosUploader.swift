import Foundation
import Photos
import Synchronization
import UniformTypeIdentifiers

struct PhotosDestination: Codable, Hashable, Sendable {
    static let defaultAlbumName = "ishare"

    var albumName: String
    var albumIdentifier: String?

    init(albumName: String = PhotosDestination.defaultAlbumName, albumIdentifier: String? = nil) {
        self.albumName = albumName
        self.albumIdentifier = albumIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case albumName = "album"
        case albumIdentifier = "albumidentifier"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        albumName = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "album")) ?? Self.defaultAlbumName
        albumIdentifier = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "albumidentifier"))
    }

    var target: PhotosAlbumTarget {
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

enum PhotosAlbumTarget: Equatable, Sendable {
    case library
    case named(String)
    case existing(identifier: String, fallbackName: String?)

    var needsFullAccess: Bool {
        self != .library
    }
}

struct PhotosAlbum: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
}

enum PhotosMediaKind: Sendable {
    case image
    case video

    init?(fileURL: URL) {
        guard let type = UTType(filenameExtension: fileURL.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .audiovisualContent) {
            self = .video
        } else {
            return nil
        }
    }
}

@MainActor
protocol PhotoLibraryClient: Sendable {
    func requestAccess(full: Bool) async -> Bool
    func save(fileURL: URL, kind: PhotosMediaKind, to album: PhotosAlbumTarget) async throws -> String
    func deleteAsset(identifier: String) async throws
    func albums() -> [PhotosAlbum]
}

@MainActor
enum PhotoLibrary {
    static var client: any PhotoLibraryClient = SystemPhotoLibrary()

    static var hasFullAccess: Bool {
        [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    static var isUndetermined: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined
    }
}

struct SystemPhotoLibrary: PhotoLibraryClient {
    func requestAccess(full: Bool) async -> Bool {
        let level: PHAccessLevel = full ? .readWrite : .addOnly
        let status = await PHPhotoLibrary.requestAuthorization(for: level)
        return status == .authorized || status == .limited
    }

    func save(fileURL: URL, kind: PhotosMediaKind, to album: PhotosAlbumTarget) async throws -> String {
        let box = CreatedAssetBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request: PHAssetChangeRequest? = switch kind {
            case .image: PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            case .video: PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            guard let placeholder = request?.placeholderForCreatedAsset else { return }
            box.identifier = placeholder.localIdentifier
            Self.albumRequest(for: album)?.addAssets([placeholder] as NSArray)
        }
        guard let identifier = box.identifier else {
            throw LocalDestinationError.photosSaveFailed("Photos couldn't import the file".localized())
        }
        return identifier
    }

    func deleteAsset(identifier: String) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    func albums() -> [PhotosAlbum] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var albums: [PhotosAlbum] = []
        result.enumerateObjects { collection, _, _ in
            albums.append(PhotosAlbum(id: collection.localIdentifier, title: collection.localizedTitle ?? ""))
        }
        return albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private nonisolated static func albumRequest(for album: PhotosAlbumTarget) -> PHAssetCollectionChangeRequest? {
        switch album {
        case .library:
            return nil
        case let .named(name):
            return existingAlbum(named: name).flatMap { PHAssetCollectionChangeRequest(for: $0) }
                ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
        case let .existing(identifier, fallbackName):
            if let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject {
                return PHAssetCollectionChangeRequest(for: collection)
            }
            return fallbackName.flatMap { albumRequest(for: .named($0)) }
        }
    }

    private nonisolated static func existingAlbum(named name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", name)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }
}

private final class CreatedAssetBox: Sendable {
    private let storedIdentifier = Mutex<String?>(nil)

    var identifier: String? {
        get { storedIdentifier.withLock { $0 } }
        set { storedIdentifier.withLock { $0 = newValue } }
    }
}

struct PhotosUploader: Uploader {
    let uploader: CustomUploader
    var library: any PhotoLibraryClient = PhotoLibrary.client

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        guard let kind = PhotosMediaKind(fileURL: fileURL) else {
            throw UploadFailure.unsupportedFile(destination: "Photos", fileExtension: fileURL.pathExtension.lowercased())
        }
        let album = (uploader.photos ?? PhotosDestination()).target
        guard await library.requestAccess(full: album.needsFullAccess) else { throw LocalDestinationError.photosAccessDenied }
        let identifier = try await library.save(fileURL: fileURL, kind: kind, to: album)
        progress(1)
        return UploadOutcome(
            url: fileURL, deletionURL: nil, uploaderID: uploader.id, s3Key: nil, localIdentifier: identifier, isShareable: false
        )
    }

    func delete(_ item: HistoryItem) async throws {
        guard let identifier = item.localIdentifier else { return }
        guard await library.requestAccess(full: true) else { throw LocalDestinationError.photosAccessDenied }
        try await library.deleteAsset(identifier: identifier)
    }
}
