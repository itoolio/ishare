//
//  Imgur.swift
//  ishare
//
//  Created by Adrian Castro on 14.07.23.
//

import Alamofire
import AppKit
import BezelNotification
import Defaults
import Foundation
import SwiftyJSON

@MainActor func imgurUpload(_ fileURL: URL, completion: @Sendable @escaping () -> Void) {
    NSLog("Starting Imgur upload for file: %@", fileURL.path)
    @Default(.imgurClientId) var imgurClientId
    let uploadManager = UploadManager.shared

    let url = "https://api.imgur.com/3/upload"

    let fileFormName = determineFileFormName(for: fileURL)
    let fileName = "ishare.\(fileURL.pathExtension)"
    let mimeType = mimeTypeForPathExtension(fileURL.pathExtension)
    NSLog("Using file form name: %@, filename: %@", fileFormName, fileName)

    AF.upload(multipartFormData: { multipartFormData in
        multipartFormData.append(fileURL, withName: fileFormName, fileName: fileName, mimeType: mimeType)
    }, to: url, method: .post, headers: ["Authorization": "Client-ID " + imgurClientId])
        .uploadProgress { progress in
            Task { @MainActor in
                uploadManager.updateProgress(fraction: progress.fractionCompleted)
            }
        }
        .response { response in
            Task { @MainActor in
                uploadManager.uploadCompleted()
                if let data = response.data {
                    let json = JSON(data)
                    if let link = json["data"]["link"].string {
                        print("Image uploaded successfully. Link: \(link)")

                        if !Defaults[.copyImageToClipboard] {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(link, forType: .string)
                        }

                        let historyItem = HistoryItem(fileUrl: link)
                        addToUploadHistory(historyItem)
                        completion()
                    } else {
                        print("Error parsing response or retrieving image link")
                        showErrorNotification()
                        completion()
                    }
                }
            }
        }
}

@MainActor
private func showErrorNotification() {
    BezelNotification.show(messageText: "An error occured", icon: ToastIcon)
}

func determineFileFormName(for fileURL: URL) -> String {
    switch fileURL.pathExtension.lowercased() {
    case "mp4", "mov":
        "video"
    default:
        "image"
    }
}
