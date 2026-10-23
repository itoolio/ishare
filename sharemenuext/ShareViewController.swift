//
//  ShareViewController.swift
//  sharemenuext
//
//  Created by Adrian Castro on 19.07.24.
//

import Cocoa
import Social
import UniformTypeIdentifiers

@MainActor
class ShareViewController: SLComposeServiceViewController {
    override func loadView() {
        // Do nothing to avoid displaying any UI
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sendFileToApp()
    }

    func sendFileToApp() {
        NSLog("Share extension activated")

        let supportedTypes: [UTType] = [
            .quickTimeMovie,
            .mpeg4Movie,
            .png,
            .jpeg,
            .heic,
            .tiff,
            .gif,
            .webP,
        ]

        guard let extensionContext,
            let item = (extensionContext.inputItems as? [NSExtensionItem])?.first,
            let provider = item.attachments?.first(where: { provider in
                supportedTypes.contains(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) })
            })
        else {
            NSLog("Error: No valid attachment found in share extension")
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let typeIdentifier = supportedTypes.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }?.identifier ?? UTType.data.identifier
        let localTypeIdentifier = typeIdentifier

        NSLog("Processing shared item of type: %@", typeIdentifier)

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            guard let item else { return }

            let processItem = { (item: any NSSecureCoding) -> URL? in
                if let urlItem = item as? URL {
                    return urlItem
                } else if let data = item as? Data {
                    guard
                        let sharedContainerURL = FileManager.default.containerURL(
                            forSecurityApplicationGroupIdentifier: Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as! String)
                    else {
                        NSLog("Failed to get shared container URL")
                        return nil
                    }

                    let tempDir = sharedContainerURL.appendingPathComponent("tmp", isDirectory: true)

                    let fileManager = FileManager.default
                    do {
                        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                    } catch {
                        NSLog("Failed to create temporary directory in shared container: \(error)")
                        return nil
                    }

                    let utType = UTType(localTypeIdentifier)
                    let fileExtension = utType?.preferredFilenameExtension ?? "dat"
                    let fileName = UUID().uuidString + "." + fileExtension
                    let fileURL = tempDir.appendingPathComponent(fileName)

                    do {
                        try data.write(to: fileURL)
                        return fileURL
                    } catch {
                        NSLog("Failed to write data to shared container URL: \(error)")
                        return nil
                    }
                }
                return nil
            }

            if let url = processItem(item) {
                if let encodedURLString = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                    let shareURL = URL(string: "ishare://upload?file=\(encodedURLString)")
                {
                    Task { @MainActor in
                        NSWorkspace.shared.open(shareURL)
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    }
                }
            } else {
                Task { @MainActor in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }
}
