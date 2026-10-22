import BezelNotification
import Defaults
import KeyboardShortcuts
import SettingsAccess
import SwiftUI

extension Color {
    static let menuAccent = Color(.displayP3, red: 0.44, green: 0.29, blue: 0.9)
}

struct MainMenuView: View {
    @EnvironmentObject var localizableManager: LocalizableManager
    @ObservedObject private var recorder = AppDelegate.shared.screenRecorder

    @Default(.copyToClipboard) var copyToClipboard
    @Default(.openInFinder) var openInFinder
    @Default(.saveToDisk) var saveToDisk
    @Default(.uploadMedia) var uploadMedia
    @Default(.openEditorAfterCapture) var openEditorAfterCapture
    @Default(.uploadType) var uploadType
    @Default(.activeCustomUploader) var activeCustomUploader
    @Default(.uploadDestination) var uploadDestination
    @Default(.builtInShare) var builtInShare
    @Default(.uploadHistory) var uploadHistory
    @Default(.menuRecordsGIF) var recordsGIF
    @Default(.aussieMode) var aussieMode

    var body: some View {
        VStack(spacing: 12) {
            header
            section("Capture") { captureRow }
            section("Record", accessory: { recordFormatPicker }) { recordSection }
            section("After Capture") { afterCaptureSection }
            if !uploadHistory.isEmpty {
                section("Recent Uploads") { recentStrip }
            }
            footer
        }
        .padding(12)
        .frame(width: 320)
        .rotationEffect(aussieMode ? .degrees(180) : .zero)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? AppIcon)
                .resizable()
                .frame(width: 24, height: 24)
            Text("ishare")
                .font(.system(size: 14, weight: .semibold))
                .fixedSize()
            Spacer(minLength: 4)
            destinationPicker
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            } preAction: {
                dismissMenu()
                NSApp.activate(ignoringOtherApps: true)
            } postAction: {}
                .buttonStyle(MenuIconButtonStyle())
                .help("Settings".localized())
                .keyboardShortcut(",")
                .accessibilityIdentifier("menu.settings")
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("About ishare".localized()) {
                dismissMenu()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(options: [
                    NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© \(Calendar.current.component(.year, from: Date())) ADRIAN CASTRO",
                ])
            }
            #if GITHUB_RELEASE
                Button("Check for Updates…".localized()) {
                    dismissMenu()
                    AppDelegate.shared.checkForUpdates()
                }
                Button("Donate".localized()) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/castdrian")!)
                }
            #endif
            Divider()
            Button("Quit".localized()) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(MenuIconButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More".localized())
        .accessibilityIdentifier("menu.more")
    }

    private func section(
        _ title: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() },
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.localized())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureRow: some View {
        HStack(spacing: 8) {
            ActionTile(symbol: "rectangle.dashed", title: "Region", shortcut: .captureRegion, identifier: "menu.capture.region") {
                run { await captureScreen(type: .REGION) }
            }
            ActionTile(symbol: "macwindow", title: "Window", shortcut: .captureWindow, identifier: "menu.capture.window") {
                run { await captureScreen(type: .WINDOW) }
            }
            if NSScreen.screens.count > 1 {
                Menu {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Button(screen.localizedName) {
                            run { await captureScreen(type: .SCREEN, display: index + 1) }
                        }
                    }
                } label: {
                    ActionTileLabel(symbol: "display.2", title: "Screen")
                }
                .menuStyle(.button)
                .buttonStyle(ActionTileStyle())
                .menuIndicator(.hidden)
                .accessibilityIdentifier("menu.capture.screen")
            } else {
                ActionTile(symbol: "display", title: "Screen", shortcut: .captureScreen, identifier: "menu.capture.screen") {
                    run { await captureScreen(type: .SCREEN) }
                }
            }
            ActionTile(symbol: "arrow.up.and.down.text.horizontal", title: "Scrolling", shortcut: .captureScrolling, identifier: "menu.capture.scrolling") {
                run { await captureScreen(type: .SCROLLING) }
            }
        }
    }

    @ViewBuilder
    private var recordFormatPicker: some View {
        if !recorder.isRunning {
            Picker("", selection: $recordsGIF) {
                Text("Video".localized()).tag(false)
                Text("GIF").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .fixedSize()
            .accessibilityIdentifier("menu.record.format")
        }
    }

    @ViewBuilder
    private var recordSection: some View {
        if recorder.isRunning {
            Button {
                AppDelegate.shared.stopRecording()
                dismissMenu()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Stop Recording".localized())
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let start = recorder.startDate {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text(Duration.seconds(context.date.timeIntervalSince(start)).formatted(.time(pattern: .minuteSecond)))
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.record.stop")
        } else {
            HStack(spacing: 8) {
                WideActionButton(
                    symbol: recordsGIF ? "photo.stack" : "record.circle",
                    title: "Screen",
                    help: "Pick a screen or window to record",
                    shortcut: recordsGIF ? .recordGif : .recordScreen,
                    identifier: recordsGIF ? "menu.record.gif" : "menu.record.screen"
                ) {
                    run { recordScreen(gif: recordsGIF) }
                }
                WideActionButton(
                    symbol: "rectangle.dashed.badge.record",
                    title: "Region",
                    shortcut: recordsGIF ? .recordRegionGif : .recordRegion,
                    identifier: recordsGIF ? "menu.record.regiongif" : "menu.record.region"
                ) {
                    run { recordScreen(gif: recordsGIF, region: true) }
                }
            }
        }
    }

    private var afterCaptureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ToggleChip(symbol: "doc.on.clipboard", title: "Copy to Clipboard", isOn: $copyToClipboard)
                ToggleChip(symbol: "internaldrive", title: "Save to Disk", isOn: Binding(
                    get: { saveToDisk },
                    set: { saveToDisk = $0; if !$0 { openInFinder = false } }
                ))
                ToggleChip(symbol: "folder", title: "Open in Finder", isOn: $openInFinder)
                    .disabled(!saveToDisk)
                ToggleChip(symbol: "icloud.and.arrow.up", title: "Upload Media", isOn: $uploadMedia)
                ToggleChip(symbol: "pencil.tip.crop.circle", title: "Open Editor", isOn: $openEditorAfterCapture)
                Divider()
                    .frame(height: 22)
                ShareChip(image: airdropIcon, title: "AirDrop", isOn: $builtInShare.airdrop)
                ShareChip(image: icon(forAppWithName: "com.apple.Photos"), title: "Photos", isOn: $builtInShare.photos)
                ShareChip(image: icon(forAppWithName: "com.apple.MobileSMS"), title: "Messages", isOn: $builtInShare.messages)
                ShareChip(image: icon(forAppWithName: "com.apple.Mail"), title: "Mail", isOn: $builtInShare.mail)
            }
            Text(afterCaptureSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var afterCaptureSummary: String {
        let enabled: [(Bool, String)] = [
            (openEditorAfterCapture, "Open Editor"),
            (copyToClipboard, "Copy to Clipboard"),
            (saveToDisk, "Save to Disk"),
            (saveToDisk && openInFinder, "Open in Finder"),
            (uploadMedia, "Upload Media"),
            (builtInShare.airdrop, "AirDrop"),
            (builtInShare.photos, "Photos"),
            (builtInShare.messages, "Messages"),
            (builtInShare.mail, "Mail"),
        ]
        let titles = enabled.filter(\.0).map { $0.1.localized() }
        return titles.isEmpty ? "Nothing happens after a capture".localized() : titles.formatted(.list(type: .and))
    }

    private var destinationTitle: String {
        if case let .custom(id) = uploadDestination, let uploader = CustomUploader.allCases.first(where: { $0.id == id }) {
            return uploader.name
        }
        return "Imgur"
    }

    private var destinationPicker: some View {
        Menu {
            Button {
                select(.builtIn(.IMGUR))
            } label: {
                Label { Text("Imgur") } icon: { Image(nsImage: ImgurIcon) }
            }
            if !CustomUploader.allCases.isEmpty {
                Divider()
                ForEach(CustomUploader.allCases) { uploader in
                    Button {
                        select(.custom(uploader.id))
                    } label: {
                        Label(uploader.name, systemImage: uploader.kind == .s3 ? "externaldrive.connected.to.line.below" : "server.rack")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text(destinationTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .frame(maxWidth: 150)
            .background(Capsule().fill(Color.primary.opacity(0.09)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Upload Destination".localized())
        .accessibilityIdentifier("menu.destination")
    }

    private func select(_ destination: UploadDestination) {
        uploadDestination = destination
        switch destination {
        case .builtIn:
            activeCustomUploader = nil
            uploadType = .IMGUR
        case let .custom(id):
            activeCustomUploader = id
            uploadType = .CUSTOM
        }
        BezelNotification.show(messageText: String(format: "Selected %@".localized(), destinationTitle), icon: ToastIcon)
    }

    private var recentStrip: some View {
        HStack(spacing: 6) {
            ForEach(uploadHistory.prefix(5), id: \.self) { item in
                RecentUploadThumbnail(item: item)
            }
            Spacer(minLength: 0)
            Button {
                dismissMenu()
                openHistoryWindow(uploadHistory: uploadHistory)
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ActionTileStyle())
            .help("Open History Window".localized())
            .accessibilityIdentifier("menu.history")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            FooterButton(symbol: "pencil.and.scribble", title: "Edit Image…") {
                run { await ImageEditor.chooseAndEdit() }
            }
            FooterButton(symbol: "doc.on.clipboard", title: "Upload Clipboard") {
                run { await AppState.uploadPasteboard() }
            }
        }
    }

    private func dismissMenu() {
        Defaults[.showMainMenu] = false
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        dismissMenu()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            await action()
        }
    }
}

@MainActor
private func shortcutHelp(_ title: String, _ shortcut: KeyboardShortcuts.Name?) -> String {
    guard let shortcut, let keys = KeyboardShortcuts.getShortcut(for: shortcut) else { return title.localized() }
    return "\(title.localized()) (\(keys.description))"
}

struct ActionTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionTileBackground(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct ActionTileBackground<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        content
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.menuAccent : Color.primary.opacity(0.08))
            )
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct ActionTileLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(height: 20)
            Text(title.localized())
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .contentShape(Rectangle())
    }
}

struct ActionTile: View {
    let symbol: String
    let title: String
    var shortcut: KeyboardShortcuts.Name?
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionTileLabel(symbol: symbol, title: title)
        }
        .buttonStyle(ActionTileStyle())
        .help(shortcutHelp(title, shortcut))
        .accessibilityIdentifier(identifier)
    }
}

struct WideActionButton: View {
    let symbol: String
    let title: String
    var help: String?
    var shortcut: KeyboardShortcuts.Name?
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(title.localized())
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionTileStyle())
        .help(shortcutHelp(help ?? title, shortcut))
        .accessibilityIdentifier(identifier)
    }
}

struct MenuIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuIconButtonBody(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct MenuIconButtonBody<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        content
            .foregroundStyle(.primary)
            .background(Circle().fill(Color.primary.opacity(isHovered || isPressed ? 0.14 : 0.07)))
            .onHover { isHovered = $0 }
    }
}

struct ToggleChip: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isOn ? Color.menuAccent : Color.primary.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.12), lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel(title.localized())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct ShareChip: View {
    let image: NSImage?
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(nsImage: image ?? NSImage())
                .resizable()
                .frame(width: 18, height: 18)
                .saturation(isOn ? 1 : 0)
                .opacity(isOn ? 1 : 0.55)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isOn ? Color.menuAccent.opacity(0.35) : Color.clear))
                .overlay(Circle().strokeBorder(isOn ? Color.menuAccent : Color.primary.opacity(0.12), lineWidth: isOn ? 1.5 : 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel(title.localized())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct FooterButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title.localized(), systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActionTileStyle())
    }
}

struct RecentUploadThumbnail: View {
    let item: HistoryItem

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.fileUrl ?? "", forType: .string)
            BezelNotification.show(messageText: "Copied URL".localized(), icon: ToastIcon)
        } label: {
            HistoryThumbnail(item: item)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(item.fileUrl ?? "")
        .contextMenu {
            Button("Copy URL".localized()) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.fileUrl ?? "", forType: .string)
            }
            Button("Open in Browser".localized()) {
                if let url = item.fileUrl.flatMap(URL.init(string:)) {
                    NSWorkspace.shared.open(url)
                }
            }
            if let path = item.localPath, FileManager.default.fileExists(atPath: path) {
                Button("Open in Editor".localized()) {
                    Task { @MainActor in await ImageEditor.editAsNewCapture(sourceURL: URL(fileURLWithPath: path)) }
                }
            }
        }
    }
}
