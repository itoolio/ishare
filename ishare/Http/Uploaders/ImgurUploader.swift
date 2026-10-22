import Alamofire
import Foundation

struct ImgurUploader: Uploader {
    let clientID: String

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let formName = ["mp4", "mov"].contains(fileURL.pathExtension.lowercased()) ? "video" : "image"
        let fileName = "ishare.\(fileURL.pathExtension.lowercased())"
        let mimeType = MimeType.forFile(fileURL)
        let request = UploadService.session.upload(
            multipartFormData: { form in
                form.append(fileURL, withName: formName, fileName: fileName, mimeType: mimeType)
            },
            to: UploadService.imgurEndpoint, method: .post, headers: ["Authorization": "Client-ID " + clientID]
        )
        let data = try await UploadService.perform(request, progress: progress)
        let link = try ResponseTemplate.render("{{data.link}}", data: data)
        guard let url = URL(string: link) else { throw UploadFailure.responseParsing(link) }
        let deleteHash = try? ResponseTemplate.render("{{data.deletehash}}", data: data)
        return UploadOutcome(
            url: url, deletionURL: deleteHash.map { "https://api.imgur.com/3/image/\($0)" }, uploaderID: nil, s3Key: nil
        )
    }

    func delete(_ item: HistoryItem) async throws {
        guard let deletionURL = item.deletionUrl, var request = UploadService.deletionRequest(for: deletionURL, uploader: nil) else { return }
        request.httpMethod = "DELETE"
        request.setValue("Client-ID " + clientID, forHTTPHeaderField: "Authorization")
        _ = try await UploadService.response(of: UploadService.session.request(request))
    }
}
