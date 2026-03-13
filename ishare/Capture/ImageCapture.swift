//
//  ImageCapture.swift
//  ishare
//
//  Created by Adrian Castro on 11.07.23.
//

import AppKit
import Defaults
import Foundation

enum CaptureType: String {
    case SCREEN = "-t"
    case WINDOW = "-wt"
    case REGION = "-it"
}

enum FileType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case PNG = "png"
    case JPG = "jpg"
    case PDF = "pdf"
    case TIFF = "tiff"
    case HEIC = "heic"
    var id: Self { self }
}

@MainActor
func captureScreen(type: CaptureType, display: Int = 1) async {
    NSLog("Starting screen capture with type: %@, display: %d", type.rawValue, display)

    let capturePath = Defaults[.capturePath]
    let fileType = Defaults[.captureFileType]
    let fileName = Defaults[.captureFileName]
    let copyToClipboard = Defaults[.copyToClipboard]
    let openInFinder = Defaults[.openInFinder]
    let uploadMedia = Defaults[.uploadMedia]
    let captureBinary = Defaults[.captureBinary]
    let uploadType = Defaults[.uploadType]
    let saveToDisk = Defaults[.saveToDisk]

    let suffix = await getCaptureNameSuffix(type: type, display: display)

    let timestamp = Int(Date().timeIntervalSince1970)
    let uniqueFilename = "\(fileName)-\(timestamp)\(suffix).\(fileType.rawValue)"

    var path = "\(capturePath)\(uniqueFilename)"
    path = NSString(string: path).expandingTildeInPath

    let task = Process()
    task.launchPath = captureBinary
    task.arguments = type == CaptureType.SCREEN ? [type.rawValue, fileType.rawValue, "-D", "\(display)", path] : [type.rawValue, fileType.rawValue, path]

    NSLog("Executing capture command: %@ %@", captureBinary, task.arguments?.joined(separator: " ") ?? "")
    task.launch()
    task.waitUntilExit()

    let fileURL = URL(fileURLWithPath: path)

    if !FileManager.default.fileExists(atPath: fileURL.path) {
        NSLog("Error: Capture file not created at path: %@", path)
        return
    }
    NSLog("Screen capture completed successfully")

    if copyToClipboard {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if Defaults[.copyImageToClipboard], let image = NSImage(contentsOf: fileURL) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(fileURL.absoluteString, forType: .fileURL)
        }
    }

    if openInFinder {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    if uploadMedia {
        let shouldSaveToDisk = saveToDisk
        let localFileURL = fileURL
        uploadFile(fileURL: fileURL, uploadType: uploadType) {
            Task { @MainActor in
                showToast(fileURL: localFileURL) {
                    NSSound.beep()

                    if !shouldSaveToDisk {
                        do {
                            try FileManager.default.removeItem(at: localFileURL)
                        } catch {
                            print("Error deleting the file: \(error)")
                        }
                    }
                }
            }
        }
    } else {
        let shouldSaveToDisk = saveToDisk
        let localFileURL = fileURL
        Task { @MainActor in
            showToast(fileURL: localFileURL) {
                NSSound.beep()

                if !shouldSaveToDisk {
                    do {
                        try FileManager.default.removeItem(at: localFileURL)
                    } catch {
                        print("Error deleting the file: \(error)")
                    }
                }
            }
        }
    }
    shareBasedOnPreferences(fileURL)
}

@MainActor
private func getCaptureNameSuffix(type: CaptureType, display: Int) async -> String {
    switch type {
    case .WINDOW:
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let appName = frontmostApp.localizedName ?? "window"
            return "-\(appName.lowercased())"
        }
        return "-window"

    case .SCREEN:
        if let screen = NSScreen.screens[safe: display - 1] {
            if let displayName = screen.localizedName {
                return "-\(displayName.lowercased())"
            }
            return "-display-\(display)"
        }
        return "-screen"

    case .REGION:
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let appName = frontmostApp.localizedName ?? "region"
            return "-\(appName.lowercased())"
        }
        return "-region"
    }
}

// Helper extension for safe array access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// Helper extension for NSScreen to get display name
extension NSScreen {
    var localizedName: String? {
        // Get the display's bounds to help identify it
        let bounds = frame
        let width = Int(bounds.width)
        let height = Int(bounds.height)

        if let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            // Check if this is the main display
            if CGDisplayIsMain(displayID) != 0 {
                return "main-\(width)x\(height)"
            }
            return "display-\(width)x\(height)"
        }
        return nil
    }
}
