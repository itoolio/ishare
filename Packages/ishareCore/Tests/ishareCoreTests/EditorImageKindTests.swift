import Testing
@testable import ishareCore

struct EditorImageKindTests {
    @Test func tellsScreenshotsPhotosAndWebPagesApart() {
        #expect(EditorImageKind.classify(fileName: "ishare-2026-11-03-Safari.png", hasCameraMetadata: false) == .screenshot)
        #expect(EditorImageKind.classify(fileName: "ishare-2026-11-03-example.com.png", hasCameraMetadata: false) == .webPage)
        #expect(EditorImageKind.classify(fileName: "IMG_1234.HEIC", hasCameraMetadata: false) == .photo)
        #expect(EditorImageKind.classify(fileName: "anything.png", hasCameraMetadata: true) == .photo)
        #expect(EditorImageKind.classify(fileName: nil, hasCameraMetadata: false) == .screenshot)
        #expect(EditorImageKind.classify(fileName: "ishare-v1.2.png", hasCameraMetadata: false) == .screenshot)
    }
}
