import BezelNotification
import Defaults
import KeyboardShortcuts
import SettingsAccess
import SwiftUI

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
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.uploadDestination) var uploadDestination
    @Default(.builtInShare) var builtInShare
    @Default(.uploadHistory) var uploadHistory
    @Default(.aussieMode) var aussieMode

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        AdaptiveGlassContainer(spacing: 10) {
            VStack(spacing: 10) {
                header
                module(title: "Capture") { captureGrid }
                module(title: "Record") { recordSection }
                module(title: "After Capture") { afterCaptureSection }
                module(title: "Upload Destination") { destinationPicker }
                if !uploadHistory.isEmpty {
                    module(title: "Recent Uploads") { recentStrip }
                }
                footer
            }
            .padding(12)
        }
        .frame(width: 372)
        .rotationEffect(aussieMode ? .degrees(180) : .zero)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage(named: "AppIcon") ?? AppIcon)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("ishare")
                    .font(.system(size: 14, weight: .bold))
                Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            } preAction: {
                dismissMenu()
                NSApp.activate(ignoringOtherApps: true)
            } postAction: {}
                .buttonStyle(.plain)
                .adaptiveGlassCapsule(interactive: true)
                .help("Settings".localized())
                .keyboardShortcut(",")
                .accessibilityIdentifier("menu.settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .adaptiveGlassCapsule(interactive: true)
            .help("Quit".localized())
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }

    private func module(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.localized())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(cornerRadius: 18)
    }

    private var captureGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ControlTile(symbol: "rectangle.dashed", title: "Region", shortcut: .captureRegion, identifier: "menu.capture.region") {
                run { await captureScreen(type: .REGION) }
            }
            ControlTile(symbol: "macwindow", title: "Window", shortcut: .captureWindow, identifier: "menu.capture.window") {
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
                    ControlTileLabel(symbol: "display.2", title: "Screen")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            } else {
                ControlTile(symbol: "display", title: "Screen", shortcut: .captureScreen, identifier: "menu.capture.screen") {
                    run { await captureScreen(type: .SCREEN) }
                }
            }
            ControlTile(symbol: "arrow.up.and.down.text.horizontal", title: "Scrolling", shortcut: .captureScrolling, identifier: "menu.capture.scrolling") {
                run { await captureScreen(type: .SCROLLING) }
            }
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
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Stop Recording".localized())
                            .font(.system(size: 13, weight: .semibold))
                        if let start = recorder.startDate {
                            TimelineView(.periodic(from: start, by: 1)) { context in
                                Text(Duration.seconds(context.date.timeIntervalSince(start)).formatted(.time(pattern: .minuteSecond)))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveGlass(cornerRadius: 14, interactive: true, tint: .red)
            .accessibilityIdentifier("menu.record.stop")
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ControlTile(symbol: "record.circle", title: "Record", shortcut: .recordScreen, identifier: "menu.record.screen") {
                    run { recordScreen(gif: false) }
                }
                ControlTile(symbol: "rectangle.dashed.badge.record", title: "Region", shortcut: .recordRegion, identifier: "menu.record.region") {
                    run { recordScreen(gif: false, region: true) }
                }
                ControlTile(symbol: "photo.stack", title: "GIF", shortcut: .recordGif, identifier: "menu.record.gif") {
                    run { recordScreen(gif: true) }
                }
                ControlTile(symbol: "square.dashed.inset.filled", title: "Region GIF", shortcut: .recordRegionGif, identifier: "menu.record.regiongif") {
                    run { recordScreen(gif: true, region: true) }
                }
            }
        }
    }

    private var afterCaptureSection: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ToggleTile(symbol: "doc.on.clipboard", title: "Copy to Clipboard", isOn: $copyToClipboard)
                ToggleTile(symbol: "internaldrive", title: "Save to Disk", isOn: Binding(
                    get: { saveToDisk },
                    set: { saveToDisk = $0; if !$0 { openInFinder = false } }
                ))
                ToggleTile(symbol: "folder", title: "Open in Finder", isOn: $openInFinder)
                    .disabled(!saveToDisk)
                ToggleTile(symbol: "icloud.and.arrow.up", title: "Upload Media", isOn: $uploadMedia)
                ToggleTile(symbol: "pencil.tip.crop.circle", title: "Open Editor", isOn: $openEditorAfterCapture)
                    .gridCellColumns(2)
            }
            HStack(spacing: 8) {
                ShareToggle(image: airdropIcon, title: "AirDrop", isOn: $builtInShare.airdrop)
                ShareToggle(image: icon(forAppWithName: "com.apple.Photos"), title: "Photos", isOn: $builtInShare.photos)
                ShareToggle(image: icon(forAppWithName: "com.apple.MobileSMS"), title: "Messages", isOn: $builtInShare.messages)
                ShareToggle(image: icon(forAppWithName: "com.apple.Mail"), title: "Mail", isOn: $builtInShare.mail)
            }
        }
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
            HStack(spacing: 10) {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .foregroundStyle(.primary)
                Text(destinationTitle)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .adaptiveGlass(cornerRadius: 12, interactive: true)
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
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(uploadHistory.prefix(8), id: \.self) { item in
                        RecentUploadThumbnail(item: item)
                    }
                }
            }
            Button {
                dismissMenu()
                openHistoryWindow(uploadHistory: uploadHistory)
            } label: {
                Image(systemName: "square.grid.2x2")
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain)
            .adaptiveGlass(cornerRadius: 10, interactive: true)
            .help("Open History Window".localized())
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            FooterButton(symbol: "pencil.and.scribble", title: "Editor") {
                dismissMenu()
                ImageEditor.chooseAndEdit()
            }
            FooterButton(symbol: "doc.on.clipboard", title: "Upload Clipboard") {
                dismissMenu()
                Task { @MainActor in await AppState.uploadPasteboard() }
            }
            FooterButton(symbol: "info.circle", title: "About") {
                dismissMenu()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(options: [
                    NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© \(Calendar.current.component(.year, from: Date())) ADRIAN CASTRO",
                ])
            }
            #if GITHUB_RELEASE
                FooterButton(symbol: "heart", title: "Donate") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/castdrian")!)
                }
                FooterButton(symbol: "arrow.triangle.2.circlepath", title: "Updates") {
                    dismissMenu()
                    AppDelegate.shared.checkForUpdates()
                }
            #endif
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

struct ControlTileLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .adaptiveGlassCapsule(interactive: true, tint: .accentColor)
            Text(title.localized())
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ControlTile: View {
    let symbol: String
    let title: String
    var shortcut: KeyboardShortcuts.Name?
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ControlTileLabel(symbol: symbol, title: title)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityIdentifier(identifier)
    }

    private var helpText: String {
        guard let shortcut, let keys = KeyboardShortcuts.getShortcut(for: shortcut) else { return title.localized() }
        return "\(title.localized()) (\(keys.description))"
    }
}

struct ToggleTile: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.1)))
                Text(title.localized())
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(6)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .adaptiveGlass(cornerRadius: 12, interactive: true, tint: isOn ? .accentColor : nil)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct ShareToggle: View {
    let image: NSImage?
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: image ?? NSImage())
                    .resizable()
                    .frame(width: 24, height: 24)
                    .saturation(isOn ? 1 : 0)
                    .opacity(isOn ? 1 : 0.6)
                Text(title.localized())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaptiveGlass(cornerRadius: 12, interactive: true, tint: isOn ? .accentColor : nil)
    }
}

struct FooterButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(title.localized())
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaptiveGlass(cornerRadius: 12, interactive: true)
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
                    Task { @MainActor in _ = await ImageEditor.edit(fileURL: URL(fileURLWithPath: path)) }
                }
            }
        }
    }
}
