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
    static let captureScrolling = Self("captureScrolling", default: .init(.s, modifiers: [.control, .option]))
    static let recordRegion = Self("recordRegion", default: .init(.r, modifiers: [.control, .option]))
    static let recordRegionGif = Self("recordRegionGif", default: .init(.f, modifiers: [.control, .option]))
    static let openEditor = Self("openEditor", default: .init(.e, modifiers: [.control, .option]))
}

enum SettingsStorage {
    static let screenshotSuiteName = "dev.adrian.ishare.screenshots"
    static let syncsToCloud = !ScreenshotMode.isActive && !ProcessInfo.processInfo.arguments.contains("-ishareDisableCloudSync")
}

extension UserDefaults {
    nonisolated(unsafe) static let ishare: UserDefaults = ScreenshotMode.isActive
        ? UserDefaults(suiteName: SettingsStorage.screenshotSuiteName) ?? .standard
        : .standard
}

extension Defaults.Keys {
    static let showMainMenu = Key<Bool>("showMainMenu", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let copyToClipboard = Key<Bool>("copyToClipboard", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let copyImageToClipboard = Key<Bool>("copyImageToClipboard", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let openInFinder = Key<Bool>("openInFinder", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let saveToDisk = Key<Bool>("saveToDisk", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadMedia = Key<Bool>("uploadMedia", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let capturePath = Key<String>("capturePath", default: "~/Pictures/", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordingPath = Key<String>("recordingPath", default: "~/Pictures/", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileType = Key<FileType>("captureFileType", default: .PNG, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileName = Key<String>("captureFileName", default: "ishare", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordingFileName = Key<String>("recordingFileName", default: "ishare", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let imgurClientId = Key<String>("imgurClientId", default: "867afe9433c0a53", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let activeCustomUploader = Key<UUID?>("activeCustomUploader", default: nil, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let savedCustomUploaders = Key<Set<CustomUploader>?>("savedCustomUploaders", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadType = Key<UploadType>("uploadType", default: .IMGUR, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadDestination = Key<UploadDestination>("uploadDestination", default: .builtIn(.IMGUR), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordMP4 = Key<Bool>("recordMP4", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let useHEVC = Key<Bool>("useHEVC", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let useHDR = Key<Bool>("useHDR", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordAudio = Key<Bool>("recordAudio", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordMic = Key<Bool>("recordMic", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordPointer = Key<Bool>("recordPointer", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordClicks = Key<Bool>("recordClicks", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let builtInShare = Key<SharingPreferences>("builtInShare", default: .init(), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let toastTimeout = Key<Double>("toastTimeout", default: 2, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let menuBarIcon = Key<MenuBarIcon>("menuBarIcon", default: .DEFAULT, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadHistory = Key<[HistoryItem]>("uploadHistory", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let ignoredBundleIdentifiers = Key<[String]>("ignoredApps", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let forceUploadModifier = Key<ForceUploadModifier>("forceUploadModifier", default: .shift, suite: .ishare)
    static let storedLanguage = Key<LanguageTypes>("storedlanguage", default: Locale.current.identifier.starts(with: "en-AU") ? .aussie : .english, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let screenshotShowsCursor = Key<Bool>("screenshotShowsCursor", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let windowShadow = Key<Bool>("windowShadow", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let showMagnifier = Key<Bool>("showMagnifier", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let openEditorAfterCapture = Key<Bool>("openEditorAfterCapture", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let scrollingAutoScroll = Key<Bool>("scrollingAutoScroll", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let capturePathBookmark = Key<Data?>("capturePathBookmark", default: nil, suite: .ishare)
    static let recordingPathBookmark = Key<Data?>("recordingPathBookmark", default: nil, suite: .ishare)
    static let recordingResolution = Key<RecordingResolution>("recordingResolution", default: .native, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordingFrameRate = Key<RecordingFrameRate>("recordingFrameRate", default: .fps60, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let gifFrameRate = Key<GIFFrameRate>("gifFrameRate", default: .fps20, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let compressBeforeUpload = Key<Bool>("compressBeforeUpload", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let compressionThresholdMB = Key<Int>("compressionThresholdMB", default: 25, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let compressionPreset = Key<CompressionPreset>("compressionPreset", default: .p1080, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let aussieMode = Key<Bool>("aussieMode", default: Locale.current.identifier.starts(with: "en-AU"), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
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
    NSApp.activate(ignoringOtherApps: true)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let uploader: CustomUploader
    do {
        uploader = try CustomUploader.fromJSON(Data(contentsOf: url))
    } catch {
        let alert = NSAlert(error: error)
        alert.messageText = "Import Error".localized()
        alert.runModal()
        return
    }
    let alert = NSAlert()
    alert.messageText = "Import ISCU".localized()
    alert.informativeText = String(format: "Do you want to import the uploader “%@”?".localized(), uploader.name)
    alert.addButton(withTitle: "Import".localized())
    alert.addButton(withTitle: "Cancel".localized())
    guard ScreenshotMode.isActive || ProcessInfo.processInfo.arguments.contains("-ishareImportWithoutConfirmation") || alert.runModal() == .alertFirstButtonReturn else { return }
    var uploaders = Defaults[.savedCustomUploaders] ?? []
    uploaders.remove(uploader)
    uploaders.insert(uploader)
    Defaults[.savedCustomUploaders] = uploaders
    Defaults[.activeCustomUploader] = uploader.id
    Defaults[.uploadType] = .CUSTOM
    Defaults[.uploadDestination] = .custom(uploader.id)
    BezelNotification.show(messageText: String(format: "Selected %@".localized(), uploader.name), icon: ToastIcon)
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
    var uploaderId: UUID?
    var s3Key: String?
    var localPath: String?
    var date: Date?
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
