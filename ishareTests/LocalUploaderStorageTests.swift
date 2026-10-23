import Defaults
import Foundation
import Testing
@testable import ishare

@MainActor
@Suite(.serialized)
struct LocalUploaderStorageTests {
    init() {
        Defaults[.savedCustomUploaders] = nil
        Defaults[.savedLocalUploaders] = []
    }

    @Test func folderAndPhotosUploadersStayOutOfTheSyncedList() {
        let folder = CustomUploader.folder(name: "Desktop", destination: FolderDestination(path: "/tmp"))
        let photos = CustomUploader.photos(name: "Album", destination: PhotosDestination())
        let http = CustomUploader(name: "web", requestURL: "https://up.example.com", headers: nil, formData: nil, fileFormName: nil, responseURL: "{{url}}")
        UploaderStore.save(folder)
        UploaderStore.save(photos)
        UploaderStore.save(http)
        #expect((Defaults[.savedCustomUploaders] ?? []).map(\.id) == [http.id])
        #expect(Set(Defaults[.savedLocalUploaders].map(\.id)) == [folder.id, photos.id])
        #expect(Set(CustomUploader.allCases.map(\.id)) == [folder.id, photos.id, http.id])
        UploaderStore.delete(folder)
        #expect(Defaults[.savedLocalUploaders].map(\.id) == [photos.id])
    }

    @Test func separatesLocalUploadersThatWereSyncedBefore() {
        let folder = CustomUploader.folder(name: "Desktop", destination: FolderDestination(path: "/tmp"))
        Defaults[.savedCustomUploaders] = [folder]
        UploaderStore.separateLocalUploaders()
        #expect(Defaults[.savedCustomUploaders]?.isEmpty == true)
        #expect(Defaults[.savedLocalUploaders].map(\.id) == [folder.id])
    }
}
