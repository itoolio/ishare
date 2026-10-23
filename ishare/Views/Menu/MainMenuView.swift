import Defaults
import SwiftUI

struct MainMenuView: View {
    var isPreview = false
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings: OpenSettingsAction
    @FocusState private var hasKeyboardFocus: Bool
    @State private var focusedTarget: MenuFocusTarget?
    @State private var previewedItem: HistoryItem?
    @State private var hoveredRecentItem: HistoryItem?
    @State private var isHoveringPreview = false
    @State private var previewTask: Task<Void, Never>?
    @State private var destinationAnchor = ViewAnchor()
    @State private var moreAnchor = ViewAnchor()
    @State private var dropTargetSection: MenuSection?

    @Default(.uploadDestination) private var uploadDestination
    @Default(.uploadHistory) private var uploadHistory
    @Default(.menuRecordsGIF) private var recordsGIF
    @Default(.aussieMode) private var aussieMode
    @Default(.menuSectionOrder) private var sectionOrder
    @Default(.hiddenMenuSections) private var hiddenSections
    @Default(.menuDensity) private var density
    @Default(.menuFavorites) private var favoriteIDs

    private var metrics: MenuMetrics { density.metrics }

    private var recorder: ScreenRecorder { app.recorder }

    private var menu: MenuController { app.menu }

    private var actions: MenuActions { app.menuActions }

    private var layout: MenuLayout {
        MenuLayout(order: sectionOrder, hidden: hiddenSections)
    }

    private var showsPalette: Bool {
        menu.showsCommandPalette && !isPreview
    }

    var body: some View {
        VStack(spacing: metrics.stackSpacing) {
            MenuHeader(isPreview: isPreview, destinationAnchor: destinationAnchor, moreAnchor: moreAnchor)
            if showsPalette {
                CommandPaletteView(onClose: closePalette)
            } else {
                if !favoriteCommands.isEmpty {
                    MenuFavoritesSection(commands: favoriteCommands, isPreview: isPreview)
                }
                ForEach(renderedSections) { section in
                    sectionView(section)
                        .menuSectionDropTarget(section, enabled: !isPreview, targeted: $dropTargetSection)
                }
            }
        }
        .padding(metrics.padding)
        .frame(width: 360)
        .environment(\.menuFocusedTarget, focusedTarget)
        .focusable(!isPreview)
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        .onAppear {
            guard !isPreview else { return }
            menu.openSettingsAction = { [openSettings] in openSettings() }
            prepareKeyboardFocus()
        }
        .onChange(of: menu.isPresented) { _, presented in
            guard !isPreview else { return }
            if presented {
                prepareKeyboardFocus()
            } else {
                closePreview()
            }
        }
        .onChange(of: menu.showsCommandPalette) { _, showing in
            guard !isPreview, !showing else { return }
            prepareKeyboardFocus()
        }
        .menuAppearance(appliesToWindow: !isPreview)
        .rotationEffect(aussieMode ? .degrees(180) : .zero)
    }

    private var renderedSections: [MenuSection] {
        layout.visibleSections.filter { $0 != .recentUploads || !uploadHistory.isEmpty }
    }

    @ViewBuilder
    private func sectionView(_ section: MenuSection) -> some View {
        switch section {
        case .capture:
            MenuSectionView("Capture", section: .capture, isPreview: isPreview) {
                MenuCaptureSection()
            }
        case .record:
            MenuSectionView("Record", section: .record, isPreview: isPreview) {
                MenuRecordFormatPicker(isRecording: recorder.isRunning, recordsGIF: $recordsGIF)
            } content: {
                MenuRecordSection(isRecording: recorder.isRunning, startDate: recorder.startDate, recordsGIF: recordsGIF)
            }
        case .afterCapture:
            MenuSectionView("After Capture", section: .afterCapture, isPreview: isPreview) {
                MenuAfterCaptureSection()
            }
        case .recentUploads:
            MenuSectionView("Recent Uploads", section: .recentUploads, isPreview: isPreview) {
                MenuRecentUploadsSection(
                    history: uploadHistory,
                    previewedItem: previewedItem,
                    onHoverItem: hoverRecent,
                    onHoverPreview: { hovering in
                        isHoveringPreview = hovering
                        schedulePreviewUpdate()
                    },
                    onClosePreview: closePreview
                )
            }
            .zIndex(1)
        case .footer:
            MenuFooter()
        }
    }

    private var favoriteCommands: [AppCommand] {
        guard !favoriteIDs.isEmpty else { return [] }
        _ = (recorder.isRunning, uploadDestination)
        return MenuFavorites(favoriteIDs).resolved(in: AppCommand.all(), id: \.id)
    }

    private var focusRows: [[MenuFocusTarget]] {
        MenuFocusLayout.rows(
            sections: renderedSections,
            isRecording: recorder.isRunning,
            chipCount: AfterCaptureStep.allCases.count,
            recentCount: min(MenuRecentUploadsSection.visibleCount, uploadHistory.count),
            showsDonate: MenuActions.showsDonate,
            favoriteCount: favoriteCommands.count
        )
    }

    private func prepareKeyboardFocus() {
        focusedTarget = nil
        hasKeyboardFocus = true
    }

    private func closePalette() {
        menu.showsCommandPalette = false
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command), press.characters.lowercased() == "k" {
            closePreview()
            menu.showsCommandPalette.toggle()
            return .handled
        }
        if press.modifiers.contains(.command), press.characters.lowercased() == "q" {
            NSApplication.shared.terminate(nil)
            return .handled
        }
        guard !showsPalette else { return .ignored }
        let directions: [KeyEquivalent: MenuFocusDirection] = [.upArrow: .up, .downArrow: .down, .leftArrow: .left, .rightArrow: .right]
        if let direction = directions[press.key] {
            closePreview()
            focusedTarget = MenuFocusNavigator.move(from: focusedTarget, aussieMode ? direction.flipped : direction, in: focusRows)
            return .handled
        }
        if press.key == .escape {
            actions.dismiss()
            return .handled
        }
        if press.key == .return || press.key == .space {
            guard let focusedTarget else { return .ignored }
            activate(focusedTarget)
            return .handled
        }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]), let character = press.characters.first else { return .ignored }
        if let index = MenuFocusNavigator.captureIndex(forKey: character) {
            actions.triggerCapture(index)
            return .handled
        }
        if MenuFocusNavigator.isRecentLinksKey(character) {
            guard !isPreview else { return .handled }
            actions.showRecentLinksMenu(history: uploadHistory, from: moreAnchor)
            return .handled
        }
        return .ignored
    }

    private func activate(_ target: MenuFocusTarget) {
        switch target {
        case .destination:
            guard !isPreview else { return }
            actions.showDestinationMenu(from: destinationAnchor)
        case .settings:
            actions.openSettings(openSettings)
        case .donate:
            guard !isPreview else { return }
            actions.openDonation()
        case .more:
            guard !isPreview else { return }
            actions.showOverflowMenu(from: moreAnchor, openWindow: openWindow)
        case let .favorite(index):
            guard let command = favoriteCommands[safe: index] else { return }
            command.perform()
        case let .capture(index):
            actions.triggerCapture(index)
        case let .record(index):
            actions.toggleRecording(gif: recordsGIF, region: index == 1)
        case .stopRecording:
            actions.stopRecording()
        case let .chip(index):
            MenuAfterCaptureSection.toggle(at: index)
        case let .recent(index):
            guard uploadHistory.indices.contains(index) else { return }
            HistoryActions.copyURL(uploadHistory[index])
        case .history:
            actions.openHistory(uploadHistory)
        case let .footer(index):
            MenuFooter.activate(index, using: actions)
        }
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
}
