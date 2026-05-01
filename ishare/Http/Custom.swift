//
//  Custom.swift
//  ishare
//
//  Created by Adrian Castro on 15.07.23.
//

import Alamofire
import AppKit
import BezelNotification
import Defaults
import Foundation
import SwiftyJSON

enum CustomUploadError: Error {
    case responseParsing
    case responseRetrieval
    case fileReadError
}

@MainActor
func customUpload(
    fileURL: URL, specification: CustomUploader,
    callback: (@Sendable ((any Error)?, URL?) -> Void)? = nil,
    completion: @Sendable @escaping () -> Void
) {
    NSLog("Starting custom upload for file: %@", fileURL.path)
    NSLog("Using uploader: %@", specification.name)

    guard specification.isValid() else {
        NSLog("Error: Invalid uploader specification")
        completion()
        return
    }

    let url = URL(string: specification.requestURL)!
    NSLog("Uploading to endpoint: %@", url.absoluteString)

    var headers = HTTPHeaders(specification.headers ?? [:])
    let fileName = fileURL.lastPathComponent
    headers.add(name: "x-file-name", value: fileName)

    switch specification.requestBodyType {
    case .multipartFormData, .none:
        uploadMultipartFormData(
            fileURL: fileURL, url: url, headers: headers, specification: specification,
            callback: callback, completion: completion
        )
    case .binary:
        uploadBinaryData(
            fileURL: fileURL, url: url, headers: &headers, specification: specification,
            callback: callback, completion: completion
        )
    }
}

@MainActor
private func uploadMultipartFormData(
    fileURL: URL, url: URL, headers: HTTPHeaders, specification: CustomUploader,
    callback: (@Sendable ((any Error)?, URL?) -> Void)?, completion: @Sendable @escaping () -> Void
) {
    let uploadManager = UploadManager.shared
    let localCallback = callback
    let localCompletion = completion

    AF.upload(
        multipartFormData: { multipartFormData in
            if let formData = specification.formData {
                for (key, value) in formData {
                    multipartFormData.append(value.data(using: .utf8)!, withName: key)
                }
            }

            let mimeType = mimeTypeForPathExtension(fileURL.pathExtension)
            let lowercasedFileName = fileNameWithLowercaseExtension(from: fileURL)
            multipartFormData.append(
                fileURL, withName: specification.fileFormName ?? "file",
                fileName: lowercasedFileName, mimeType: mimeType
            )

        }, to: url, method: .post, headers: headers
    )
    .uploadProgress { progress in
        Task { @MainActor in
            uploadManager.updateProgress(fraction: progress.fractionCompleted)
        }
    }
    .response { response in
        Task { @MainActor in
            uploadManager.uploadCompleted()
            print(response)
            if let data = response.data {
                handleResponse(
                    data: data, specification: specification, callback: localCallback,
                    completion: localCompletion
                )
            } else {
                localCallback?(CustomUploadError.responseRetrieval, nil)
                localCompletion()
            }
        }
    }
}

@MainActor
private func uploadBinaryData(
    fileURL: URL, url: URL, headers: inout HTTPHeaders, specification: CustomUploader,
    callback: (@Sendable ((any Error)?, URL?) -> Void)?, completion: @Sendable @escaping () -> Void
) {
    let uploadManager = UploadManager.shared
    let localCallback = callback
    let localCompletion = completion
    let mimeType = mimeTypeForPathExtension(fileURL.pathExtension)
    headers.add(name: "Content-Type", value: mimeType)

    AF.upload(fileURL, to: url, method: .post, headers: headers)
        .uploadProgress { progress in
            Task { @MainActor in
                uploadManager.updateProgress(fraction: progress.fractionCompleted)
            }
        }
        .response { response in
            Task { @MainActor in
                uploadManager.uploadCompleted()
                if let data = response.data {
                    handleResponse(
                        data: data, specification: specification, callback: localCallback,
                        completion: localCompletion
                    )
                } else {
                    localCallback?(CustomUploadError.responseRetrieval, nil)
                    localCompletion()
                }
            }
        }
}

@MainActor
private func handleResponse(
    data: Data, specification: CustomUploader, callback: (@Sendable ((any Error)?, URL?) -> Void)?,
    completion: @Sendable () -> Void
) {
    let json = JSON(data)
    let fileUrl = constructUrl(from: specification.responseURL, using: json)
    let deletionUrl = constructUrl(from: specification.deletionURL, using: json)

    if let fileUrl = URL(string: fileUrl) {
        let historyItem = HistoryItem(fileUrl: fileUrl.absoluteString, deletionUrl: deletionUrl)
        addToUploadHistory(historyItem)

        if !Defaults[.copyImageToClipboard] {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(fileUrl.absoluteString, forType: .string)
        }
        callback?(nil, fileUrl)
    } else {
        callback?(CustomUploadError.responseParsing, nil)
    }
    completion()
}

private func constructUrl(from format: String?, using json: JSON) -> String {
    guard let format else { return "" }
    let (taggedUrl, tags) = tagPlaceholders(in: format)
    var url = taggedUrl

    for (tag, keyPath) in tags {
        if let replacement = getNestedJSONValue(json: json, keyPath: keyPath) {
            url = url.replacingOccurrences(of: tag, with: replacement)
        }
    }

    return url
}

private func tagPlaceholders(in url: String) -> (taggedUrl: String, tags: [(String, String)]) {
    var taggedUrl = url
    var tags: [(String, String)] = []

    let pattern = "\\{\\{([^}]+)\\}\\}"
    let regex = try? NSRegularExpression(pattern: pattern, options: [])
    let nsrange = NSRange(url.startIndex ..< url.endIndex, in: url)

    regex?.enumerateMatches(in: url, options: [], range: nsrange) { match, _, _ in
        if let match, let range = Range(match.range(at: 1), in: url) {
            let key = String(url[range])
            let tag = "%%\(key)_TAG%%"
            tags.append((tag, key))
            taggedUrl = taggedUrl.replacingOccurrences(of: "{{\(key)}}", with: tag)
        }
    }
    return (taggedUrl, tags)
}

private func getNestedJSONValue(json: JSON, keyPath: String) -> String? {
    var currentJSON = json
    let keyPathElements = keyPath.components(separatedBy: ".")

    for element in keyPathElements {
        // Splitting the element to handle nested arrays and objects
        let subElements = element.split(whereSeparator: { $0 == "[" || $0 == "]" }).map(String.init)

        for subElement in subElements {
            if let index = Int(subElement) {
                // Access array by index
                currentJSON = currentJSON[index]
            } else {
                // Access object by key
                currentJSON = currentJSON[subElement]
            }
        }

        // Check if the JSON element is valid
        if currentJSON == JSON.null {
            return "failed to extract json value for \(element)"
        }
    }

    return currentJSON.stringValue
}

private func fileNameWithLowercaseExtension(from url: URL) -> String {
    let fileName = url.lastPathComponent
    let fileExtension = url.pathExtension.lowercased()
    return fileName.replacingOccurrences(of: url.pathExtension, with: fileExtension)
}

func mimeTypeForPathExtension(_ ext: String) -> String {
    switch ext.lowercased() {
    case "jpg", "jpeg":
        "image/jpeg"
    case "png":
        "image/png"
    case "gif":
        "image/gif"
    case "pdf":
        "application/pdf"
    case "mp4":
        "video/mp4"
    case "mov":
        "video/quicktime"
    default:
        "application/octet-stream"
    }
}

@MainActor
func performDeletionRequest(
    deletionUrl: String, completion: @Sendable @escaping (Result<String, any Error>) -> Void
) {
    guard let url = URL(string: deletionUrl) else {
        completion(.failure(CustomUploadError.responseParsing))
        return
    }

    @Default(.activeCustomUploader) var activeCustomUploader
    let uploader = CustomUploader.allCases.first(where: { $0.id == activeCustomUploader })
    let headers = HTTPHeaders(uploader?.headers ?? [:])

    func sendRequest(with method: HTTPMethod) {
        AF.request(url, method: method, headers: headers).response { response in
            Task { @MainActor in
                switch response.result {
                case .success:
                    completion(.success("Deleted file successfully"))
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        }
    }

    switch uploader?.deleteRequestType {
    case .get:
        sendRequest(with: .get)
    case .delete:
        sendRequest(with: .delete)
    case nil:
        sendRequest(with: .get)
    }
}
