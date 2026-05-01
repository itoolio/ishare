//
//  Constants.swift
//  ishare
//
//  Created by Adrian Castro on 12.07.23.
//

import Alamofire
import AVFoundation
import BezelNotification
import Carbon
import Defaults
import KeyboardShortcuts
import ScreenCaptureKit
import SwiftUI
import SwiftyJSON
import Zip

extension KeyboardShortcuts.Name {
    static let noKeybind = Self("noKeybind")
    static let toggleMainMenu = Self("toggleMainMenu", default: .init(.s, modifiers: [.option, .command]))
    static let captureRegion = Self("captureRegion", default: .init(.p, modifiers: [.option, .command]))
    static let captureWindow = Self("captureWindow", default: .init(.p, modifiers: [.control, .option]))
    static let captureScreen = Self("captureScreen", default: .init(.x, modifiers: [.option, .command]))
    static let recordScreen = Self("recordScreen", default: .init(.z, modifiers: [.control, .option]))
    static let recordGif = Self("recordGif", default: .init(.g, modifiers: [.control, .option]))
    static let openHistoryWindow = Self("openHistoryWindow", default: .init(.k, modifiers: [.command, .option]))
    
    static let openMostRecentItem = Self("openMostRecentItem", default: .init(.o, modifiers: [.control, .option]))
    static let uploadPasteBoardItem = Self("uploadPasteBoardItem", default: .init(.u, modifiers: [.control, .option]))


    // Force upload variants
    static let captureRegionForceUpload = Self("captureRegionForceUpload", default: .init(.p, modifiers: [.shift, .option, .command]))
    static let captureWindowForceUpload = Self("captureWindowForceUpload", default: .init(.p, modifiers: [.shift, .control, .option]))
    static let captureScreenForceUpload = Self("captureScreenForceUpload", default: .init(.x, modifiers: [.shift, .option, .command]))
    static let recordScreenForceUpload = Self("recordScreenForceUpload", default: .init(.z, modifiers: [.shift, .control, .option]))
    static let recordGifForceUpload = Self("recordGifForceUpload", default: .init(.g, modifiers: [.shift, .control, .option]))
}

extension Defaults.Keys {
    static let showMainMenu = Key<Bool>("showMainMenu", default: false, iCloud: true)
    static let copyToClipboard = Key<Bool>("copyToClipboard", default: true, iCloud: true)
    static let copyImageToClipboard = Key<Bool>("copyImageToClipboard", default: false, iCloud: true)
    static let openInFinder = Key<Bool>("openInFinder", default: false, iCloud: true)
    static let saveToDisk = Key<Bool>("saveToDisk", default: true, iCloud: true)
    static let uploadMedia = Key<Bool>("uploadMedia", default: false, iCloud: true)
    static let capturePath = Key<String>("capturePath", default: "~/Pictures/", iCloud: true)
    static let recordingPath = Key<String>("recordingPath", default: "~/Pictures/", iCloud: true)
    static let captureFileType = Key<FileType>("captureFileType", default: .PNG, iCloud: true)
    static let captureFileName = Key<String>("captureFileName", default: "ishare", iCloud: true)
    static let recordingFileName = Key<String>("recordingFileName", default: "ishare", iCloud: true)
    static let imgurClientId = Key<String>("imgurClientId", default: "867afe9433c0a53", iCloud: true)
    static let captureBinary = Key<String>("captureBinary", default: "/usr/sbin/screencapture", iCloud: true)
    static let activeCustomUploader = Key<UUID?>("activeCustomUploader", default: nil, iCloud: true)
    static let savedCustomUploaders = Key<Set<CustomUploader>?>("savedCustomUploaders", iCloud: true)
    static let uploadType = Key<UploadType>("uploadType", default: .IMGUR, iCloud: true)
    static let uploadDestination = Key<UploadDestination>("uploadDestination", default: .builtIn(.IMGUR), iCloud: true)
    static let recordMP4 = Key<Bool>("recordMP4", default: true, iCloud: true)
    static let useHEVC = Key<Bool>("useHEVC", default: false, iCloud: true)
    static let useHDR = Key<Bool>("useHDR", default: false, iCloud: true)
    static let recordAudio = Key<Bool>("recordAudio", default: true, iCloud: true)
    static let recordMic = Key<Bool>("recordMic", default: false, iCloud: true)
    static let recordPointer = Key<Bool>("recordPointer", default: true, iCloud: true)
    static let recordClicks = Key<Bool>("recordClicks", default: false, iCloud: true)
    static let builtInShare = Key<SharingPreferences>("builtInShare", default: .init(), iCloud: true)
    static let toastTimeout = Key<Double>("toastTimeout", default: 2, iCloud: true)
    static let menuBarIcon = Key<MenuBarIcon>("menuBarIcon", default: .DEFAULT, iCloud: true)
    static let uploadHistory = Key<[HistoryItem]>("uploadHistory", default: [], iCloud: true)
    static let ignoredBundleIdentifiers = Key<[String]>("ignoredApps", default: [], iCloud: true)
    static let forceUploadModifier = Key<ForceUploadModifier>("forceUploadModifier", default: .shift)
    static let storedLanguage = Key<LanguageTypes>("storedlanguage", default: Locale.current.identifier.starts(with: "en-AU") ? .aussie : .english, iCloud: true)
    static let aussieMode = Key<Bool>("aussieMode", default: Locale.current.identifier.starts(with: "en-AU"), iCloud: true)
}

extension KeyboardShortcuts.Shortcut {
    func toKeyEquivalent() -> KeyEquivalent? {
        let carbonKeyCode = UInt16(carbonKeyCode)
        let maxNameLength = 4
        var nameBuffer = [UniChar](repeating: 0, count: maxNameLength)
        var nameLength = 0

        let modifierKeys = UInt32(alphaLock >> 8) & 0xFF // Caps Lock
        var deadKeys: UInt32 = 0
        let keyboardType = UInt32(LMGetKbdType())

        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            NSLog("Could not get keyboard layout data")
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        let osStatus = layoutData.withUnsafeBytes {
            UCKeyTranslate($0.bindMemory(to: UCKeyboardLayout.self).baseAddress, carbonKeyCode, UInt16(kUCKeyActionDown),
                           modifierKeys, keyboardType, UInt32(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeys, maxNameLength, &nameLength, &nameBuffer)
        }
        guard osStatus == noErr else {
            NSLog("Code: 0x%04X  Status: %+i", carbonKeyCode, osStatus)
            return nil
        }

        return KeyEquivalent(Character(String(utf16CodeUnits: nameBuffer, count: nameLength)))
    }

    func toEventModifiers() -> SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []

        if self.modifiers.contains(NSEvent.ModifierFlags.command) {
            modifiers.update(with: EventModifiers.command)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.control) {
            modifiers.update(with: EventModifiers.control)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.option) {
            modifiers.update(with: EventModifiers.option)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.shift) {
            modifiers.update(with: EventModifiers.shift)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.capsLock) {
            modifiers.update(with: EventModifiers.capsLock)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.numericPad) {
            modifiers.update(with: EventModifiers.numericPad)
        }

        return modifiers
    }
}

extension utsname {
    static var sMachine: String {
        var utsname = utsname()
        uname(&utsname)
        return withUnsafePointer(to: &utsname.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    static var isAppleSilicon: Bool {
        sMachine == "arm64"
    }
}

@MainActor
func selectFolder(completion: @escaping @Sendable (URL?) -> Void) {
    let folderPicker = NSOpenPanel()
    folderPicker.canChooseDirectories = true
    folderPicker.canChooseFiles = false
    folderPicker.allowsMultipleSelection = false
    folderPicker.canDownloadUbiquitousContents = true
    folderPicker.canResolveUbiquitousConflicts = true

    Task {
        let response = await folderPicker.beginAsyncModal()
        if response == .OK {
            completion(folderPicker.urls.first)
        } else {
            completion(nil)
        }
    }
}

@MainActor
func importIscu(_ url: URL) {
    NSLog("Starting ISCU import process for file: %@", url.path)
    if let keyWindow = NSApplication.shared.keyWindow {
        let alert = NSAlert()
        alert.messageText = "Import ISCU"
        alert.informativeText = "Do you want to import this custom uploader?"
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        NSLog("Showing import confirmation dialog")
        alert.beginSheetModal(for: keyWindow) { response in
            if response == .alertFirstButtonReturn {
                NSLog("User confirmed import")
                
                Task { @MainActor in
                    alert.window.orderOut(nil)
                    
                    do {
                        let data = try Data(contentsOf: url)
                        let decoder = JSONDecoder()
                        let uploader = try decoder.decode(CustomUploader.self, from: data)

                        @Default(.savedCustomUploaders) var savedCustomUploaders
                        @Default(.activeCustomUploader) var activeCustomUploader
                        @Default(.uploadType) var uploadType

                        if var uploaders = savedCustomUploaders {
                            uploaders.remove(uploader)
                            uploaders.insert(uploader)
                            savedCustomUploaders = uploaders
                        } else {
                            savedCustomUploaders = Set([uploader])
                        }

                        activeCustomUploader = uploader.id
                        uploadType = .CUSTOM
                        
                        NSLog("ISCU import successful")
                        let successAlert = NSAlert()
                        successAlert.messageText = "Import Successful"
                        successAlert.informativeText = "The custom uploader has been imported successfully."
                        successAlert.addButton(withTitle: "OK")
                        successAlert.runModal()
                    } catch {
                        NSLog("ISCU import failed: %@", error.localizedDescription)
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "Import Error"
                        errorAlert.informativeText = error.localizedDescription
                        errorAlert.addButton(withTitle: "OK")
                        errorAlert.runModal()
                    }
                }
            } else {
                NSLog("User cancelled import")
            }
        }
    }
}

@MainActor
let AppIcon: NSImage = {
    let appIconImage = NSImage(named: "AppIcon")
    let ratio = (appIconImage?.size.height)! / (appIconImage?.size.width)!
    let newSize = NSSize(width: 18, height: 18 / ratio)
    let resizedImage = NSImage(size: newSize)
    resizedImage.lockFocus()
    appIconImage?.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: appIconImage!.size), operation: .copy, fraction: 1.0)
    resizedImage.unlockFocus()
    return resizedImage
}()

@MainActor
let ImgurIcon: NSImage = {
    let appIconImage = NSImage(named: "Imgur")
    let ratio = (appIconImage?.size.height)! / (appIconImage?.size.width)!
    let newSize = NSSize(width: 18, height: 18 / ratio)
    let resizedImage = NSImage(size: newSize)
    resizedImage.lockFocus()
    appIconImage?.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: appIconImage!.size), operation: .copy, fraction: 1.0)
    resizedImage.unlockFocus()
    return resizedImage
}()

@MainActor
let ToastIcon: NSImage = {
    let toastIconImage = NSImage(named: "AppIcon")
    let ratio = (toastIconImage?.size.height)! / (toastIconImage?.size.width)!
    let newSize = NSSize(width: 100, height: 100 / ratio)
    let resizedImage = NSImage(size: newSize)
    resizedImage.lockFocus()
    toastIconImage?.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: toastIconImage!.size), operation: .copy, fraction: 1.0)
    resizedImage.unlockFocus()
    return resizedImage
}()

@MainActor
func icon(forAppWithName appName: String) -> NSImage? {
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
    return nil
}

let airdropIconPath = Bundle.path(forResource: "AirDrop", ofType: "icns", inDirectory: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources")

@MainActor let airdropIcon = NSImage(contentsOfFile: airdropIconPath!)

struct SharingPreferences: Codable, Defaults.Serializable {
    var airdrop: Bool = false
    var photos: Bool = false
    var messages: Bool = false
    var mail: Bool = false
}

@MainActor
func shareBasedOnPreferences(_ fileURL: URL) {
    NSLog("Processing share preferences for file: %@", fileURL.path)
    let preferences = Defaults[.builtInShare]

    if preferences.airdrop {
        NSLog("Sharing via AirDrop")
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [fileURL])
    }

    if preferences.photos {
        NSLog("Adding to Photos")
        NSSharingService(named: .addToIPhoto)?.perform(withItems: [fileURL])
    }

    if preferences.messages {
        NSLog("Sharing via Messages")
        NSSharingService(named: .composeMessage)?.perform(withItems: [fileURL])
    }

    if preferences.mail {
        NSLog("Sharing via Mail")
        NSSharingService(named: .composeEmail)?.perform(withItems: [fileURL])
    }
}

enum MenuBarIcon: Codable, CaseIterable, Identifiable, Defaults.Serializable {
    case DEFAULT
    case APPICON
    case SYSTEM
    var id: Self { self }
}

struct HistoryItem: Codable, Hashable, Defaults.Serializable {
    var fileUrl: String?
    var deletionUrl: String?
    var id: Self { self }
}

func addToUploadHistory(_ item: HistoryItem) {
    NSLog("Adding item to upload history: %@", item.fileUrl ?? "nil")
    var history = Defaults[.uploadHistory]
    history.insert(item, at: 0)
    if history.count > 50 {
        NSLog("Upload history exceeded 50 items, removing oldest entry")
        history.removeLast()
    }
    Defaults[.uploadHistory] = history
}

@MainActor
struct ExcludedAppsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Default(.ignoredBundleIdentifiers) var ignoredBundleIdentifiers

    var body: some View {
        VStack {
            Text("Select apps to exclude")
                .font(.title)

            Divider()

            ScrollView {
                ForEach(NSWorkspace.shared.runningApplications.sorted { $0.localizedName ?? "" < $1.localizedName ?? "" }.filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }, id: \.self) { app in
                    Toggle(isOn: Binding(
                        get: {
                            ignoredBundleIdentifiers.contains(app.bundleIdentifier ?? "")
                        },
                        set: { newValue in
                            if newValue {
                                ignoredBundleIdentifiers.append(app.bundleIdentifier ?? "")
                            } else {
                                ignoredBundleIdentifiers.removeAll { $0 == app.bundleIdentifier }
                            }
                        }
                    )) {
                        Text(app.localizedName ?? app.bundleIdentifier ?? "unknown")
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Spacer()

            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.bottom)
        }
        .padding()
    }
}

enum ForceUploadModifier: String, CaseIterable, Identifiable, Defaults.Serializable {
    case shift = "⇧"
    case control = "⌃"
    case option = "⌥"
    case command = "⌘"

    var id: Self { self }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }
}

enum UploadDestination: Equatable, Hashable, Codable, Defaults.Serializable {
    case builtIn(UploadType)
    case custom(UUID?)
}

@MainActor
class WindowHolder: Sendable {
    static let shared = WindowHolder()
    var historyWindowController: HistoryWindowController?
}

@MainActor
class HistoryWindowController: NSWindowController {
    convenience init(contentView: NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.center()
        window.contentView = contentView
        self.init(window: window)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }
}

@MainActor
func openHistoryWindow(uploadHistory _: [HistoryItem]) {
    if WindowHolder.shared.historyWindowController == nil {
        let historyView = HistoryGridView()
        let hostingController = NSHostingController(rootView: historyView)
        let windowController = HistoryWindowController(contentView: hostingController.view)
        windowController.window?.title = "History".localized()

        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        WindowHolder.shared.historyWindowController = windowController
    } else {
        WindowHolder.shared.historyWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
