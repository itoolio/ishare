import BezelNotification
import Defaults
import KeyboardShortcuts
import SettingsAccess
import SwiftUI

extension Color {
    static let menuAccent = Color(.displayP3, red: 0.44, green: 0.29, blue: 0.9)
}

struct MainMenuView: View {
    @ObservedObject private var recorder = AppDelegate.shared.screenRecorder
    @ObservedObject private var menu = MenuController.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings: OpenSettingsAction
    @FocusState private var hasKeyboardFocus: Bool
    @State private var focusedTarget: MenuFocusTarget?
    @State private var previewedItem: HistoryItem?
    @State private var hoveredRecentItem: HistoryItem?
    @State private var isHoveringPreview = false
    @State private var previewTask: Task<Void, Never>?

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
        .environment(\.menuFocusedTarget, focusedTarget)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        .onAppear(perform: prepareKeyboardFocus)
        .onChange(of: menu.isPresented) { _, presented in
            if presented {
                prepareKeyboardFocus()
            } else {
                closePreview()
            }
        }
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
                .menuFocusRing(.settings, shape: .circle)
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
            Button("Welcome Guide…".localized()) {
                dismissMenu()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: Onboarding.windowID)
            }
            .accessibilityIdentifier("menu.onboarding")
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
                triggerCapture(0)
            }
            .menuFocusRing(.capture(0))
            ActionTile(symbol: "macwindow", title: "Window", shortcut: .captureWindow, identifier: "menu.capture.window") {
                triggerCapture(1)
            }
            .menuFocusRing(.capture(1))
            if NSScreen.screens.count > 1 {
                Menu {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Button(screen.localizedName) {
                            run { await CaptureSession.captureImage(.SCREEN, display: index + 1) }
                        }
                    }
                } label: {
                    ActionTileLabel(symbol: "display.2", title: "Screen")
                }
                .menuStyle(.button)
                .buttonStyle(ActionTileStyle())
                .menuIndicator(.hidden)
                .menuFocusRing(.capture(2))
                .accessibilityIdentifier("menu.capture.screen")
            } else {
                ActionTile(symbol: "display", title: "Screen", shortcut: .captureScreen, identifier: "menu.capture.screen") {
                    triggerCapture(2)
                }
                .menuFocusRing(.capture(2))
            }
            ActionTile(symbol: "arrow.up.and.down.text.horizontal", title: "Scrolling", shortcut: .captureScrolling, identifier: "menu.capture.scrolling") {
                triggerCapture(3)
            }
            .menuFocusRing(.capture(3))
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
                CaptureSession.stopRecording()
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
            .menuFocusRing(.stopRecording)
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
                    run { CaptureSession.toggleRecording(gif: recordsGIF) }
                }
                .menuFocusRing(.record(0))
                WideActionButton(
                    symbol: "rectangle.dashed.badge.record",
                    title: "Region",
                    shortcut: recordsGIF ? .recordRegionGif : .recordRegion,
                    identifier: recordsGIF ? "menu.record.regiongif" : "menu.record.region"
                ) {
                    run { CaptureSession.toggleRecording(gif: recordsGIF, region: true) }
                }
                .menuFocusRing(.record(1))
            }
        }
    }

    private var afterCaptureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ToggleChip(symbol: "doc.on.clipboard", title: "Copy to Clipboard", isOn: chipBindings[0])
                    .menuFocusRing(.chip(0), shape: .circle)
                ToggleChip(symbol: "internaldrive", title: "Save to Disk", isOn: chipBindings[1])
                    .menuFocusRing(.chip(1), shape: .circle)
                ToggleChip(symbol: "folder", title: "Open in Finder", isOn: chipBindings[2])
                    .disabled(!saveToDisk)
                    .menuFocusRing(.chip(2), shape: .circle)
                ToggleChip(symbol: "icloud.and.arrow.up", title: "Upload Media", isOn: chipBindings[3])
                    .menuFocusRing(.chip(3), shape: .circle)
                ToggleChip(symbol: "pencil.tip.crop.circle", title: "Open Editor", isOn: chipBindings[4])
                    .menuFocusRing(.chip(4), shape: .circle)
                Divider()
                    .frame(height: 22)
                ShareChip(image: airdropIcon, title: "AirDrop", isOn: chipBindings[5])
                    .menuFocusRing(.chip(5), shape: .circle)
                ShareChip(image: icon(forAppWithName: "com.apple.Photos"), title: "Photos", isOn: chipBindings[6])
                    .menuFocusRing(.chip(6), shape: .circle)
                ShareChip(image: icon(forAppWithName: "com.apple.MobileSMS"), title: "Messages", isOn: chipBindings[7])
                    .menuFocusRing(.chip(7), shape: .circle)
                ShareChip(image: icon(forAppWithName: "com.apple.Mail"), title: "Mail", isOn: chipBindings[8])
                    .menuFocusRing(.chip(8), shape: .circle)
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
        .menuFocusRing(.destination, shape: .roundedRectangle(13))
        .accessibilityValue(destinationTitle)
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
            ForEach(Array(uploadHistory.prefix(5).enumerated()), id: \.element) { index, item in
                RecentUploadThumbnail(item: item, index: index) { hovering in
                    hoverRecent(hovering ? item : nil)
                }
                .menuFocusRing(.recent(index), shape: .roundedRectangle(8))
            }
            Spacer(minLength: 0)
            Button {
                openHistory()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ActionTileStyle())
            .help("Open History Window".localized())
            .menuFocusRing(.history)
            .accessibilityIdentifier("menu.history")
        }
        .overlay(alignment: .bottomLeading) {
            if let previewedItem {
                RecentUploadPreview(item: previewedItem, uploaderName: previewedItem.uploaderName(among: CustomUploader.allCases)) { hovering in
                    isHoveringPreview = hovering
                    schedulePreviewUpdate()
                } onFinish: {
                    closePreview()
                }
                .offset(y: -52)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .animation(.snappy(duration: 0.18), value: previewedItem)
        .zIndex(1)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            FooterButton(symbol: "pencil.and.scribble", title: "Edit Image…") {
                run { await ImageEditor.chooseAndEdit() }
            }
            .menuFocusRing(.footer(0))
            .accessibilityIdentifier("menu.editImage")
            FooterButton(symbol: "doc.on.clipboard", title: "Upload Clipboard") {
                run { await AppState.uploadPasteboard() }
            }
            .menuFocusRing(.footer(1))
            .accessibilityIdentifier("menu.uploadClipboard")
        }
    }

    private var chipBindings: [Binding<Bool>] {
        [
            $copyToClipboard,
            Binding(get: { saveToDisk }, set: { saveToDisk = $0; if !$0 { openInFinder = false } }),
            $openInFinder,
            $uploadMedia,
            $openEditorAfterCapture,
            $builtInShare.airdrop,
            $builtInShare.photos,
            $builtInShare.messages,
            $builtInShare.mail,
        ]
    }

    private var focusRows: [[MenuFocusTarget]] {
        var rows: [[MenuFocusTarget]] = [[.destination, .settings], (0 ..< 4).map(MenuFocusTarget.capture)]
        rows.append(recorder.isRunning ? [.stopRecording] : [.record(0), .record(1)])
        rows.append(chipBindings.indices.map(MenuFocusTarget.chip))
        if !uploadHistory.isEmpty {
            rows.append((0 ..< min(5, uploadHistory.count)).map(MenuFocusTarget.recent) + [.history])
        }
        rows.append([.footer(0), .footer(1)])
        return rows
    }

    private func prepareKeyboardFocus() {
        focusedTarget = nil
        hasKeyboardFocus = true
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let directions: [KeyEquivalent: MenuFocusDirection] = [.upArrow: .up, .downArrow: .down, .leftArrow: .left, .rightArrow: .right]
        if let direction = directions[press.key] {
            closePreview()
            focusedTarget = MenuFocusNavigator.move(from: focusedTarget, aussieMode ? direction.flipped : direction, in: focusRows)
            return .handled
        }
        if press.key == .escape {
            dismissMenu()
            return .handled
        }
        if press.key == .return || press.key == .space {
            guard let focusedTarget else { return .ignored }
            activate(focusedTarget)
            return .handled
        }
        if press.modifiers.isDisjoint(with: [.command, .control, .option]),
           let character = press.characters.first,
           let index = MenuFocusNavigator.captureIndex(forKey: character)
        {
            triggerCapture(index)
            return .handled
        }
        return .ignored
    }

    private func activate(_ target: MenuFocusTarget) {
        switch target {
        case .destination:
            selectNextDestination()
        case .settings:
            dismissMenu()
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        case let .capture(index):
            triggerCapture(index)
        case let .record(index):
            run { CaptureSession.toggleRecording(gif: recordsGIF, region: index == 1) }
        case .stopRecording:
            CaptureSession.stopRecording()
            dismissMenu()
        case let .chip(index):
            guard chipBindings.indices.contains(index), index != 2 || saveToDisk else { return }
            chipBindings[index].wrappedValue.toggle()
        case let .recent(index):
            guard uploadHistory.indices.contains(index) else { return }
            HistoryActions.copyURL(uploadHistory[index])
        case .history:
            openHistory()
        case let .footer(index):
            if index == 0 {
                run { await ImageEditor.chooseAndEdit() }
            } else {
                run { await AppState.uploadPasteboard() }
            }
        }
    }

    private func triggerCapture(_ index: Int) {
        let types: [CaptureType] = [.REGION, .WINDOW, .SCREEN, .SCROLLING]
        guard types.indices.contains(index) else { return }
        let type = types[index]
        run { await CaptureSession.captureImage(type) }
    }

    private func selectNextDestination() {
        let destinations = [UploadDestination.builtIn(.IMGUR)] + CustomUploader.allCases.map { UploadDestination.custom($0.id) }
        let current = destinations.firstIndex(of: uploadDestination) ?? -1
        select(destinations[(current + 1) % destinations.count])
    }

    private func openHistory() {
        dismissMenu()
        openHistoryWindow(uploadHistory: uploadHistory)
    }

    private func hoverRecent(_ item: HistoryItem?) {
        hoveredRecentItem = item
        schedulePreviewUpdate()
    }

    private func schedulePreviewUpdate() {
        previewTask?.cancel()
        if let target = hoveredRecentItem {
            guard target != previewedItem else { return }
            let delay: Duration = previewedItem == nil ? .milliseconds(400) : .milliseconds(120)
            previewTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                previewedItem = target
            }
        } else if !isHoveringPreview, previewedItem != nil {
            previewTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                previewedItem = nil
            }
        }
    }

    private func closePreview() {
        previewTask?.cancel()
        previewedItem = nil
        hoveredRecentItem = nil
        isHoveringPreview = false
    }

    private func dismissMenu() {
        MenuController.shared.dismiss()
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        MenuController.shared.perform(afterDismissing: action)
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
    let index: Int
    let onHover: (Bool) -> Void

    var body: some View {
        Button {
            HistoryActions.copyURL(item)
        } label: {
            HistoryThumbnail(item: item, pointSize: 44)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .contextMenu { HistoryItemMenuItems(item: item, showsFinder: false) }
        .accessibilityLabel(item.fileName)
        .accessibilityIdentifier("menu.recent.\(index)")
    }
}

struct RecentUploadPreview: View {
    let item: HistoryItem
    let uploaderName: String?
    let onHover: (Bool) -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(width: 272, height: 150)
                .overlay { HistoryThumbnail(item: item, pointSize: 280, contentMode: .fit) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let url = item.fileUrl {
                    Text(url)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                ToastActionButton(symbol: "doc.on.doc", title: "Copy URL", identifier: "menu.preview.copy") {
                    HistoryActions.copyURL(item)
                    onFinish()
                }
                .disabled(item.fileUrl == nil)
                ToastActionButton(symbol: "safari", title: "Open", iconOnly: true, identifier: "menu.preview.open") {
                    onFinish()
                    MenuController.shared.dismiss()
                    HistoryActions.open(item)
                }
                if HistoryActions.canEdit(item) {
                    ToastActionButton(symbol: "pencil.tip.crop.circle", title: "Edit", iconOnly: true, identifier: "menu.preview.edit") {
                        onFinish()
                        HistoryActions.edit(item)
                    }
                }
                Menu {
                    if item.canDeleteFromServer {
                        Button("Delete from Server…".localized(), role: .destructive) {
                            onFinish()
                            HistoryActions.confirmDeleteFromServer(item)
                        }
                    }
                    Button("Remove from History".localized()) {
                        onFinish()
                        HistoryActions.removeFromHistory(item)
                    }
                } label: {
                    ToastActionLabel(symbol: "trash", title: "Delete", iconOnly: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Delete".localized())
                .accessibilityIdentifier("menu.preview.delete")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .onHover(perform: onHover)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu.preview")
    }

    private var metadata: String {
        let date = item.date?.formatted(date: .abbreviated, time: .shortened)
        return [date, uploaderName].compactMap { $0 }.joined(separator: " · ")
    }
}
