import Alamofire
import Foundation
import ishareCore

enum CloudStorageError: LocalizedError, Equatable {
    case missingField(String)
    case missingUploadLocation

    var errorDescription: String? {
        switch self {
        case let .missingField(field):
            String(format: "The cloud storage response is missing %@".localized(), field)
        case .missingUploadLocation:
            "The cloud storage didn't return an upload location".localized()
        }
    }
}

struct APIRequest: Equatable, Sendable {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Data?

    var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        return request
    }

    static func json(_ method: String, _ url: URL, token: String?, body: Any? = nil, headers: [String: String] = [:]) -> APIRequest {
        var allHeaders = headers
        if let token {
            allHeaders["Authorization"] = "Bearer \(token)"
        }
        var data: Data?
        if let body {
            data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
            allHeaders["Content-Type"] = "application/json"
        }
        return APIRequest(method: method, url: url, headers: allHeaders, body: data)
    }
}

enum JSONValue {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UploadFailure.responseParsing(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return object
    }

    static func string(_ object: [String: Any], _ path: String...) -> String? {
        var current: Any? = object
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current as? String
    }

    static func require(_ object: [String: Any], _ path: String...) throws -> String {
        var current: Any? = object
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        guard let value = current as? String, !value.isEmpty else { throw CloudStorageError.missingField(path.joined(separator: ".")) }
        return value
    }
}

@MainActor
enum CloudHTTP {
    static func send(_ request: APIRequest) async throws -> Data {
        try await UploadService.response(of: UploadService.session.request(request.urlRequest))
    }

    static func sendJSON(_ request: APIRequest) async throws -> [String: Any] {
        try JSONValue.object(try await send(request))
    }

    static func upload(_ fileURL: URL, to url: URL, method: HTTPMethod, headers: [String: String], progress: @escaping @Sendable (Double) -> Void) async throws -> Data {
        let request = UploadService.session.upload(fileURL, to: url, method: method, headers: HTTPHeaders(headers))
        return try await UploadService.perform(request, progress: progress)
    }
}

enum DropboxAPI {
    static let upload = URL(string: "https://content.dropboxapi.com/2/files/upload")!
    static let createSharedLink = URL(string: "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings")!
    static let listSharedLinks = URL(string: "https://api.dropboxapi.com/2/sharing/list_shared_links")!
    static let delete = URL(string: "https://api.dropboxapi.com/2/files/delete_v2")!
    static let currentAccount = URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!
    static let uploadSessionStart = URL(string: "https://content.dropboxapi.com/2/files/upload_session/start")!
    static let uploadSessionAppend = URL(string: "https://content.dropboxapi.com/2/files/upload_session/append_v2")!
    static let uploadSessionFinish = URL(string: "https://content.dropboxapi.com/2/files/upload_session/finish")!

    static func sessionHeaders(argument: [String: Any], token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/octet-stream",
            "Dropbox-API-Arg": apiArgument(argument),
        ]
    }

    static func apiArgument(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return asciiEscaped(String(decoding: data, as: UTF8.self))
    }

    static func asciiEscaped(_ json: String) -> String {
        json.utf16.reduce(into: "") { result, unit in
            if unit < 0x80 {
                result.append(Character(Unicode.Scalar(unit)!))
            } else {
                result += String(format: "\\u%04x", unit)
            }
        }
    }

    static func uploadHeaders(path: String, token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/octet-stream",
            "Dropbox-API-Arg": apiArgument(["path": "/" + path, "mode": "add", "autorename": true, "mute": true]),
        ]
    }

    static func sharedLinkRequest(path: String, token: String) -> APIRequest {
        .json("POST", createSharedLink, token: token, body: ["path": path, "settings": ["requested_visibility": "public", "audience": "public", "access": "viewer"]])
    }

    static func listSharedLinksRequest(path: String, token: String) -> APIRequest {
        .json("POST", listSharedLinks, token: token, body: ["path": path, "direct_only": true])
    }

    static func deleteRequest(id: String, token: String) -> APIRequest {
        .json("POST", delete, token: token, body: ["path": id])
    }

    static func existingLink(fromConflict body: String?) -> String? {
        guard let body, let object = try? JSONValue.object(Data(body.utf8)) else { return nil }
        return JSONValue.string(object, "error", "shared_link_already_exists", "metadata", "url")
    }

    static func directURL(_ link: String) -> String {
        guard var components = URLComponents(string: link) else { return link }
        var items = (components.queryItems ?? []).filter { $0.name != "dl" && $0.name != "raw" }
        items.append(URLQueryItem(name: "raw", value: "1"))
        components.queryItems = items
        return components.string ?? link
    }
}

enum GoogleDriveAPI {
    static let folderMimeType = "application/vnd.google-apps.folder"
    static let files = URL(string: "https://www.googleapis.com/drive/v3/files")!
    static let about = URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress,displayName)")!
    static let resumableUpload = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name,webViewLink,webContentLink")!

    static func escapedQueryValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    static func folderSearchRequest(name: String, parent: String, token: String) -> APIRequest {
        let query = "name = '\(escapedQueryValue(name))' and mimeType = '\(folderMimeType)' and '\(escapedQueryValue(parent))' in parents and trashed = false"
        var components = URLComponents(url: files, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "pageSize", value: "1"),
        ]
        return .json("GET", components.url!, token: token)
    }

    static func createFolderRequest(name: String, parent: String, token: String) -> APIRequest {
        .json("POST", URL(string: files.absoluteString + "?fields=id")!, token: token, body: ["name": name, "mimeType": folderMimeType, "parents": [parent]])
    }

    static func startUploadRequest(name: String, parent: String, mimeType: String, size: Int, token: String) -> APIRequest {
        .json(
            "POST", resumableUpload, token: token, body: ["name": name, "parents": [parent]],
            headers: [
                "X-Upload-Content-Type": mimeType, "X-Upload-Content-Length": String(size),
            ])
    }

    static func permissionRequest(fileID: String, token: String) -> APIRequest {
        .json("POST", files.appending(path: fileID).appending(path: "permissions"), token: token, body: ["role": "reader", "type": "anyone"])
    }

    static func deleteRequest(fileID: String, token: String) -> APIRequest {
        .json("DELETE", files.appending(path: fileID), token: token)
    }
}

enum OneDriveAPI {
    static let simpleUploadLimit = 4 * 1024 * 1024
    static let chunkSize = 32 * 320 * 1024
    static let drive = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!
    static let me = URL(string: "https://graph.microsoft.com/v1.0/me?$select=displayName,mail,userPrincipalName")!

    static func itemURL(path: String, suffix: String) -> URL {
        URL(string: "\(drive.absoluteString)/root:/\(S3Path.encode(path)):/\(suffix)")!
    }

    static func simpleUploadURL(path: String) -> URL {
        URL(string: itemURL(path: path, suffix: "content").absoluteString + "?@microsoft.graph.conflictBehavior=rename")!
    }

    static func uploadSessionRequest(path: String, token: String) -> APIRequest {
        .json("POST", itemURL(path: path, suffix: "createUploadSession"), token: token, body: ["item": ["@microsoft.graph.conflictBehavior": "rename"]])
    }

    static func createLinkRequest(itemID: String, token: String, anonymous: Bool) -> APIRequest {
        var body: [String: Any] = ["type": "view"]
        if anonymous {
            body["scope"] = "anonymous"
        }
        return .json("POST", drive.appending(path: "items").appending(path: itemID).appending(path: "createLink"), token: token, body: body)
    }

    static func deleteRequest(itemID: String, token: String) -> APIRequest {
        .json("DELETE", drive.appending(path: "items").appending(path: itemID), token: token)
    }

    static func chunkRanges(size: Int, chunkSize: Int = chunkSize) -> [Range<Int>] {
        stride(from: 0, to: max(size, 1), by: chunkSize).map { $0 ..< min($0 + chunkSize, size) }
    }

    static func contentRange(_ range: Range<Int>, total: Int) -> String {
        "bytes \(range.lowerBound)-\(max(range.lowerBound, range.upperBound - 1))/\(total)"
    }
}

@MainActor
enum CloudAccounts {
    static func accountName(provider: CloudProvider, accessToken: String) async throws -> String? {
        switch provider {
        case .dropbox:
            var request = APIRequest.json("POST", DropboxAPI.currentAccount, token: accessToken)
            request.body = Data("null".utf8)
            request.headers["Content-Type"] = "application/json"
            let object = try await CloudHTTP.sendJSON(request)
            return JSONValue.string(object, "email") ?? JSONValue.string(object, "name", "display_name")
        case .googleDrive:
            let object = try await CloudHTTP.sendJSON(.json("GET", GoogleDriveAPI.about, token: accessToken))
            return JSONValue.string(object, "user", "emailAddress") ?? JSONValue.string(object, "user", "displayName")
        case .oneDrive:
            let object = try await CloudHTTP.sendJSON(.json("GET", OneDriveAPI.me, token: accessToken))
            return JSONValue.string(object, "userPrincipalName") ?? JSONValue.string(object, "mail") ?? JSONValue.string(object, "displayName")
        }
    }
}

@MainActor
enum DriveFolderCache {
    static var identifiers: [String: String] = [:]
}

struct CloudStorageUploader: Uploader {
    let uploader: CustomUploader
    let provider: CloudProvider
    var now: @Sendable () -> Date = { Date() }
    var dropboxSessionThreshold = DropboxUploadSession.singleRequestLimit
    var dropboxChunkSize = DropboxUploadSession.defaultChunkSize

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        let configuration = uploader.cloud ?? CloudStorageConfiguration()
        let path = try configuration.remotePath(fileName: fileURL.lastPathComponent, date: now())
        return try await OAuthSession.withAccessToken(for: uploader, provider: provider) { token in
            switch provider {
            case .dropbox:
                try await uploadToDropbox(fileURL, path: path, token: token, configuration: configuration, progress: progress)
            case .googleDrive:
                try await uploadToDrive(fileURL, path: path, token: token, progress: progress)
            case .oneDrive:
                try await uploadToOneDrive(fileURL, path: path, token: token, progress: progress)
            }
        }
    }

    func delete(_ item: HistoryItem) async throws {
        guard let identifier = item.s3Key, !identifier.isEmpty else { return }
        try await OAuthSession.withAccessToken(for: uploader, provider: provider) { token in
            switch provider {
            case .dropbox:
                _ = try await CloudHTTP.send(DropboxAPI.deleteRequest(id: identifier, token: token))
            case .googleDrive:
                _ = try await CloudHTTP.send(GoogleDriveAPI.deleteRequest(fileID: identifier, token: token))
            case .oneDrive:
                _ = try await CloudHTTP.send(OneDriveAPI.deleteRequest(itemID: identifier, token: token))
            }
        }
    }

    private func outcome(_ link: String, identifier: String) throws -> UploadOutcome {
        guard let url = URL(string: link), url.scheme != nil else { throw UploadFailure.responseParsing(link) }
        return UploadOutcome(url: url, deletionURL: nil, uploaderID: uploader.id, s3Key: identifier)
    }

    private func uploadToDropbox(
        _ fileURL: URL, path: String, token: String, configuration: CloudStorageConfiguration, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadOutcome {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let data: Data
        if DropboxUploadSession.usesSession(size: size, limit: dropboxSessionThreshold) {
            data = try await uploadDropboxSession(fileURL, path: path, size: size, token: token, progress: progress)
        } else {
            data = try await CloudHTTP.upload(fileURL, to: DropboxAPI.upload, method: .post, headers: DropboxAPI.uploadHeaders(path: path, token: token), progress: progress)
        }
        let metadata = try JSONValue.object(data)
        let identifier = try JSONValue.require(metadata, "id")
        let displayPath = JSONValue.string(metadata, "path_lower") ?? JSONValue.string(metadata, "path_display") ?? "/" + path
        let link = try await dropboxSharedLink(path: displayPath, token: token)
        return try outcome(configuration.directLink == true ? DropboxAPI.directURL(link) : link, identifier: identifier)
    }

    private func uploadDropboxSession(
        _ fileURL: URL, path: String, size: Int, token: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var sessionID: String?
        var offset = 0
        var corrections = 0
        while true {
            let step = DropboxUploadSession.nextStep(offset: offset, size: size, chunkSize: dropboxChunkSize, started: sessionID != nil)
            try handle.seek(toOffset: UInt64(step.range.lowerBound))
            let chunk = step.range.isEmpty ? Data() : try handle.read(upToCount: step.range.count) ?? Data()
            do {
                switch step {
                case .start:
                    let response = try await sendDropboxChunk(chunk, to: DropboxAPI.uploadSessionStart, argument: DropboxUploadSession.startArgument(), token: token)
                    sessionID = try JSONValue.require(try JSONValue.object(response), "session_id")
                case .append:
                    let argument = DropboxUploadSession.appendArgument(sessionID: sessionID ?? "", offset: step.range.lowerBound)
                    _ = try await sendDropboxChunk(chunk, to: DropboxAPI.uploadSessionAppend, argument: argument, token: token)
                case .finish:
                    let argument = DropboxUploadSession.finishArgument(sessionID: sessionID ?? "", offset: step.range.lowerBound, path: "/" + path)
                    let metadata = try await sendDropboxChunk(chunk, to: DropboxAPI.uploadSessionFinish, argument: argument, token: token)
                    progress(1)
                    return metadata
                }
                offset = step.range.upperBound
                progress(Double(offset) / Double(max(size, 1)))
            } catch let UploadFailure.http(status, body) {
                guard sessionID != nil, let correct = DropboxUploadSession.correctOffset(fromErrorBody: body), (0 ... size).contains(correct),
                    corrections < DropboxUploadSession.maximumOffsetCorrections
                else { throw UploadFailure.http(status: status, body: body) }
                Log.upload.info("Dropbox expected offset \(correct) instead of \(step.range.lowerBound), resuming from there")
                corrections += 1
                offset = correct
            }
        }
    }

    private func sendDropboxChunk(_ chunk: Data, to url: URL, argument: [String: Any], token: String) async throws -> Data {
        let request = UploadService.session.upload(chunk, to: url, method: .post, headers: HTTPHeaders(DropboxAPI.sessionHeaders(argument: argument, token: token)))
        return try await UploadService.perform(request) { _ in }
    }

    private func dropboxSharedLink(path: String, token: String) async throws -> String {
        do {
            return try JSONValue.require(try await CloudHTTP.sendJSON(DropboxAPI.sharedLinkRequest(path: path, token: token)), "url")
        } catch let UploadFailure.http(status, body) where status == 409 {
            if let existing = DropboxAPI.existingLink(fromConflict: body) { return existing }
            let listed = try await CloudHTTP.sendJSON(DropboxAPI.listSharedLinksRequest(path: path, token: token))
            guard let links = listed["links"] as? [[String: Any]], let url = links.first?["url"] as? String else {
                throw UploadFailure.http(status: status, body: body)
            }
            return url
        }
    }

    private func driveFolderID(for directories: [String], token: String) async throws -> String {
        var parent = "root"
        for name in directories {
            let cacheKey = "\(uploader.id.uuidString)/\(parent)/\(name)"
            if let cached = DriveFolderCache.identifiers[cacheKey] {
                parent = cached
                continue
            }
            let found = try await CloudHTTP.sendJSON(GoogleDriveAPI.folderSearchRequest(name: name, parent: parent, token: token))
            let identifier: String
            if let existing = (found["files"] as? [[String: Any]])?.first?["id"] as? String {
                identifier = existing
            } else {
                identifier = try JSONValue.require(try await CloudHTTP.sendJSON(GoogleDriveAPI.createFolderRequest(name: name, parent: parent, token: token)), "id")
            }
            DriveFolderCache.identifiers[cacheKey] = identifier
            parent = identifier
        }
        return parent
    }

    private func uploadToDrive(_ fileURL: URL, path: String, token: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let segments = path.split(separator: "/").map(String.init)
        let name = segments.last ?? fileURL.lastPathComponent
        let parent = try await driveFolderID(for: Array(segments.dropLast()), token: token)
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let mimeType = MimeType.forFile(fileURL)
        let start = GoogleDriveAPI.startUploadRequest(name: name, parent: parent, mimeType: mimeType, size: size, token: token)
        let (_, response) = try await UploadService.responseWithHeaders(of: UploadService.session.request(start.urlRequest))
        guard let location = response.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)) else {
            throw CloudStorageError.missingUploadLocation
        }
        let data = try await CloudHTTP.upload(fileURL, to: location, method: .put, headers: ["Authorization": "Bearer \(token)", "Content-Type": mimeType], progress: progress)
        let file = try JSONValue.object(data)
        let identifier = try JSONValue.require(file, "id")
        _ = try await CloudHTTP.send(GoogleDriveAPI.permissionRequest(fileID: identifier, token: token))
        let link = JSONValue.string(file, "webViewLink") ?? "https://drive.google.com/file/d/\(identifier)/view"
        return try outcome(link, identifier: identifier)
    }

    private func uploadToOneDrive(_ fileURL: URL, path: String, token: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let item: [String: Any]
        if size <= OneDriveAPI.simpleUploadLimit {
            let data = try await CloudHTTP.upload(
                fileURL, to: OneDriveAPI.simpleUploadURL(path: path), method: .put,
                headers: ["Authorization": "Bearer \(token)", "Content-Type": MimeType.forFile(fileURL)], progress: progress
            )
            item = try JSONValue.object(data)
        } else {
            item = try await uploadOneDriveSession(fileURL, path: path, size: size, token: token, progress: progress)
        }
        let identifier = try JSONValue.require(item, "id")
        let link: String
        do {
            link = try JSONValue.require(try await CloudHTTP.sendJSON(OneDriveAPI.createLinkRequest(itemID: identifier, token: token, anonymous: true)), "link", "webUrl")
        } catch let UploadFailure.http(status, _) where (400 ..< 500).contains(status) && status != 401 {
            link = try JSONValue.require(try await CloudHTTP.sendJSON(OneDriveAPI.createLinkRequest(itemID: identifier, token: token, anonymous: false)), "link", "webUrl")
        }
        return try outcome(link, identifier: identifier)
    }

    private func uploadOneDriveSession(
        _ fileURL: URL, path: String, size: Int, token: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [String: Any] {
        let session = try await CloudHTTP.sendJSON(OneDriveAPI.uploadSessionRequest(path: path, token: token))
        guard let uploadURL = JSONValue.string(session, "uploadUrl").flatMap(URL.init(string:)) else {
            throw CloudStorageError.missingUploadLocation
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var last = Data()
        for range in OneDriveAPI.chunkRanges(size: size) {
            try handle.seek(toOffset: UInt64(range.lowerBound))
            let chunk = try handle.read(upToCount: range.count) ?? Data()
            let request = UploadService.session.upload(
                chunk, to: uploadURL, method: .put,
                headers: [
                    "Content-Range": OneDriveAPI.contentRange(range, total: size)
                ])
            last = try await UploadService.perform(request) { _ in }
            progress(Double(range.upperBound) / Double(max(size, 1)))
        }
        return try JSONValue.object(last)
    }
}
