import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case capture
    case recording
    case uploaders
    case keybinds
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .capture: "Screenshots"
        case .recording: "Recordings"
        case .uploaders: "Uploaders"
        case .keybinds: "Keybinds"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .capture: "camera.viewfinder"
        case .recording: "record.circle"
        case .uploaders: "icloud.and.arrow.up.fill"
        case .keybinds: "command"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .capture: .blue
        case .recording: .red
        case .uploaders: .teal
        case .keybinds: .purple
        case .advanced: .orange
        }
    }
}

struct SettingsView: View {
    @Default(.aussieMode) var aussieMode
    @State private var selection: SettingsPane? = ScreenshotMode.initialSettingsPane ?? .general
    @State private var searchText = ""
    @ObservedObject private var navigator = SettingsNavigator.shared

    private var matches: [SettingsSearchMatch] {
        SettingsSearchIndex.matches(for: searchText)
    }

    var body: some View {
        NavigationSplitView {
            List(matches, id: \.pane, selection: $selection) { match in
                NavigationLink(value: match.pane) {
                    SettingsPaneRow(pane: match.pane, keyword: match.keyword, isSearching: !searchText.isEmpty)
                }
                .accessibilityIdentifier("settings.pane.\(match.pane.rawValue)")
            }
            .overlay {
                if matches.isEmpty {
                    Text("No Results".localized())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .top) {
                SettingsSearchField(text: $searchText)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 2) {
                    Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("ishare.itoolio.dev", destination: URL(string: "https://ishare.itoolio.dev")!)
                        .font(.caption)
                }
                .padding(.bottom, 10)
            }
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralSettingsView()
                case .capture: CaptureSettingsView()
                case .recording: RecordingSettingsView()
                case .uploaders: UploaderSettingsView()
                case .keybinds: KeybindSettingsView()
                case .advanced: AdvancedSettingsView()
                }
            }
            .navigationTitle((selection ?? .general).title.localized())
            .rotationEffect(aussieMode ? .degrees(180) : .zero)
        }
        .frame(width: 760, height: 560)
        .onChange(of: searchText) {
            guard let first = matches.first, !searchText.isEmpty else { return }
            if !matches.contains(where: { $0.pane == selection }) {
                selection = first.pane
            }
        }
        .onAppear(perform: applyRequestedPane)
        .onChange(of: navigator.pane) { applyRequestedPane() }
    }

    private func applyRequestedPane() {
        guard let pane = navigator.pane else { return }
        searchText = ""
        selection = pane
        navigator.pane = nil
    }
}

struct SettingsPaneRow: View {
    let pane: SettingsPane
    let keyword: String?
    let isSearching: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pane.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(pane.title.localized())
                    .fontWeight(isSearching ? .semibold : .regular)
                if let keyword {
                    Text(keyword.localized().trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct FolderRow: View {
    let title: String
    let kind: SaveLocation.Kind
    @Default(.capturePath) private var capturePath
    @Default(.recordingPath) private var recordingPath

    private var path: String {
        kind == .captures ? capturePath : recordingPath
    }

    var body: some View {
        LabeledContent(title.localized()) {
            HStack {
                Text(NSString(string: path).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Choose…".localized()) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
                    Task { @MainActor in
                        if await panel.beginAsyncModal() == .OK, let url = panel.url {
                            SaveLocation.choose(url, for: kind)
                        }
                    }
                }
                Button {
                    NSWorkspace.shared.open(SaveLocation.directory(for: kind))
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open in Finder".localized())
            }
        }
    }
}

struct PrefixRow: View {
    let key: Defaults.Key<String>
    @State private var value = ""

    var body: some View {
        LabeledContent("File prefix:".localized()) {
            HStack {
                TextField("", text: Binding(get: { Defaults[key] }, set: { Defaults[key] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button {
                    Defaults[key] = key.defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Set to default".localized())
            }
        }
    }
}

struct GeneralSettingsView: View {
    @State private var language = AppLanguage.override()
    @State private var pendingLanguage: LanguageTypes??
    @Default(.menuBarIcon) var menubarIcon
    @Default(.toastTimeout) var toastTimeout
    @Default(.aussieMode) var aussieMode
    @Default(.copyImageToClipboard) var copyImageToClipboard

    var body: some View {
        Form {
            Section {
                Picker("Language".localized(), selection: Binding(
                    get: { language },
                    set: { if $0 != language { pendingLanguage = .some($0) } }
                )) {
                    Text("System Default".localized()).tag(LanguageTypes?.none)
                    Divider()
                    ForEach(LanguageTypes.allCases, id: \.self) { language in
                        Text(language.name).tag(LanguageTypes?.some(language))
                    }
                }
                LaunchAtLogin.Toggle {
                    Text("Launch at login".localized())
                }
                Toggle("Land down under".localized(), isOn: $aussieMode)
            }
            Section("Menu Bar Icon".localized()) {
                Picker("Menu Bar Icon".localized(), selection: $menubarIcon) {
                    Image(.menubar).tag(MenuBarIcon.DEFAULT)
                    Image(nsImage: AppIcon).tag(MenuBarIcon.APPICON)
                    Image(systemName: "photo.on.rectangle.angled").tag(MenuBarIcon.SYSTEM)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Clipboard".localized()) {
                Toggle("Copy image to clipboard instead of URL".localized(), isOn: $copyImageToClipboard)
            }
            Section("Toast".localized()) {
                LabeledContent(String(format: "Toast Timeout: %d seconds".localized(), Int(toastTimeout))) {
                    Slider(value: $toastTimeout, in: 1 ... 10, step: 1)
                        .frame(width: 220)
                }
            }
            SoundSettingsSection()
            HistorySettingsSection()
        }
        .formStyle(.grouped)
        .alert("Language Change".localized(), isPresented: Binding(
            get: { pendingLanguage != nil },
            set: { if !$0 { pendingLanguage = nil } }
        )) {
            Button("Restart Now".localized(), role: .destructive) {
                guard let choice = pendingLanguage else { return }
                AppLanguage.set(choice)
                language = choice
                AppLanguage.relaunch()
            }
            Button("Cancel".localized(), role: .cancel) {}
        } message: {
            Text("ishare restarts to apply the new language.".localized())
        }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent(title.localized()) {
            if granted {
                Label("Allowed".localized(), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…".localized(), action: action)
            }
        }
    }
}

struct CaptureSettingsView: View {
    @Default(.captureFileType) var fileType
    @Default(.screenshotShowsCursor) var showsCursor
    @Default(.windowShadow) var windowShadow
    @Default(.showMagnifier) var showMagnifier
    @Default(.openEditorAfterCapture) var openEditorAfterCapture
    @Default(.scrollingAutoScroll) var scrollingAutoScroll
    @State private var screenAccess = CGPreflightScreenCaptureAccess()
    @State private var eventAccess = CGPreflightPostEventAccess()

    var body: some View {
        Form {
            Section("Files".localized()) {
                Picker("Format:".localized(), selection: $fileType) {
                    ForEach(FileType.allCases) { Text($0.rawValue.uppercased()).tag($0) }
                }
                PrefixRow(key: .captureFileName)
                FolderRow(title: "Image path:", kind: .captures)
            }
            Section("Capture".localized()) {
                Toggle("Show pointer in screenshots".localized(), isOn: $showsCursor)
                Toggle("Include window shadow".localized(), isOn: $windowShadow)
                Toggle("Show magnifier while selecting".localized(), isOn: $showMagnifier)
                Toggle("Open editor after capture".localized(), isOn: $openEditorAfterCapture)
            }
            CaptureExtrasSettings()
            Section("Scrolling Capture".localized()) {
                Toggle("Scroll automatically".localized(), isOn: $scrollingAutoScroll)
                if scrollingAutoScroll {
                    PermissionRow(title: "Scrolling permission", granted: eventAccess) {
                        PermissionGuide.show(.accessibility)
                    }
                }
            }
            Section("Permissions".localized()) {
                PermissionRow(title: "Screen recording", granted: screenAccess) {
                    PermissionGuide.show(.screenRecording)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            screenAccess = CGPreflightScreenCaptureAccess()
            eventAccess = CGPreflightPostEventAccess()
        }
    }
}

struct RecordingSettingsView: View {
    @Default(.recordMP4) var recordMP4
    @Default(.useHEVC) var useHEVC
    @Default(.useHDR) var useHDR
    @Default(.recordAudio) var recordAudio
    @Default(.recordMic) var recordMic
    @Default(.recordPointer) var recordPointer
    @Default(.recordClicks) var recordClicks
    @Default(.recordingResolution) var resolution
    @Default(.recordingFrameRate) var frameRate
    @Default(.gifFrameRate) var gifFrameRate
    @Default(.compressBeforeUpload) var compressBeforeUpload
    @Default(.compressionThresholdMB) var compressionThresholdMB
    @Default(.compressionPreset) var compressionPreset
    @Default(.ignoredBundleIdentifiers) var ignoredBundleIdentifiers
    @State private var isExcludedAppSheetPresented = false

    var body: some View {
        Form {
            Section("Video".localized()) {
                Picker("Resolution".localized(), selection: $resolution) {
                    ForEach(RecordingResolution.allCases) { Text($0.title.localized()).tag($0) }
                }
                .accessibilityIdentifier("settings.recording.resolution")
                Picker("Frame rate".localized(), selection: $frameRate) {
                    ForEach(RecordingFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0) }
                }
                Toggle("Record .mp4 instead of .mov".localized(), isOn: $recordMP4)
                Toggle("Use HEVC".localized(), isOn: $useHEVC)
                Toggle("Use HDR".localized(), isOn: $useHDR)
            }
            Section("Content".localized()) {
                Toggle("Record audio".localized(), isOn: $recordAudio)
                Toggle("Record microphone".localized(), isOn: $recordMic)
                    .onChange(of: recordMic) { _, enabled in
                        guard enabled else { return }
                        Task { @MainActor in
                            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                                if !granted { recordMic = false }
                            }
                        }
                    }
                Toggle("Record pointer".localized(), isOn: $recordPointer)
                Toggle("Record clicks".localized(), isOn: $recordClicks)
                LabeledContent("Excluded applications".localized()) {
                    HStack {
                        Text("\(ignoredBundleIdentifiers.count)")
                            .foregroundStyle(.secondary)
                        Button("Edit…".localized()) { isExcludedAppSheetPresented = true }
                    }
                }
            }
            RecordingExtrasSettings()
            Section("GIF".localized()) {
                Picker("GIF frame rate".localized(), selection: $gifFrameRate) {
                    ForEach(GIFFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0) }
                }
            }
            Section("Upload".localized()) {
                Toggle("Compress large recordings before upload".localized(), isOn: $compressBeforeUpload)
                if compressBeforeUpload {
                    Stepper(value: $compressionThresholdMB, in: 1 ... 4000, step: 5) {
                        LabeledContent("Larger than".localized(), value: "\(compressionThresholdMB) MB")
                    }
                    Picker("Compress to".localized(), selection: $compressionPreset) {
                        ForEach(CompressionPreset.allCases) { Text($0.title.localized()).tag($0) }
                    }
                }
            }
            Section("Files".localized()) {
                PrefixRow(key: .recordingFileName)
                FolderRow(title: "Video path:", kind: .recordings)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isExcludedAppSheetPresented) {
            ExcludedAppsView()
                .frame(width: 380, height: 460)
        }
    }
}

struct KeybindSettingsView: View {
    @Default(.forceUploadModifier) var forceUploadModifier

    static let groups: [(String, [(String, KeyboardShortcuts.Name)])] = [
        ("Capture", [
            ("Capture Region:", .captureRegion),
            ("Capture Window:", .captureWindow),
            ("Capture Screen:", .captureScreen),
            ("Scrolling Capture:", .captureScrolling),
            ("Capture Last Region:", .captureLastRegion),
        ]),
        ("Record", [
            ("Record Screen:", .recordScreen),
            ("Record Region:", .recordRegion),
            ("Record GIF:", .recordGif),
            ("Record Region as GIF:", .recordRegionGif),
        ]),
        ("Capture and Upload", [
            ("Capture Region:", .captureRegionForceUpload),
            ("Capture Window:", .captureWindowForceUpload),
            ("Capture Screen:", .captureScreenForceUpload),
            ("Record Screen:", .recordScreenForceUpload),
            ("Record GIF:", .recordGifForceUpload),
        ]),
        ("Other", [
            ("Open Main Menu:", .toggleMainMenu),
            ("Open History Window:", .openHistoryWindow),
            ("Open Editor:", .openEditor),
            ("Open most recent item:", .openMostRecentItem),
            ("Upload from Pasteboard:", .uploadPasteBoardItem),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0.localized()) {
                    ForEach(group.1, id: \.1.rawValue) { entry in
                        KeyboardShortcuts.Recorder(entry.0.localized(), name: entry.1)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    KeyboardShortcuts.reset(Self.groups.flatMap { $0.1.map(\.1) })
                    BezelNotification.show(messageText: "Reset keybinds".localized(), icon: ToastIcon)
                } label: {
                    Text("Reset All Keybinds".localized())
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettingsView: View {
    @Default(.imgurClientId) var imgurClientId

    var body: some View {
        Form {
            Section {
                Text("Warning! Only modify these settings if you know what you're doing!".localized())
                    .foregroundStyle(.secondary)
            }
            Section("Imgur".localized()) {
                LabeledContent("Imgur Client ID:".localized()) {
                    HStack {
                        TextField("", text: $imgurClientId)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                        Button {
                            imgurClientId = Defaults.Keys.imgurClientId.defaultValue
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Set to default".localized())
                    }
                }
            }
            SettingsTransferSection()
        }
        .formStyle(.grouped)
    }
}
