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
    @State private var revealTask: Task<Void, Never>?

    @EnvironmentObject private var app: AppModel

    private var navigator: SettingsNavigator { app.settings }

    private var matches: [SettingsSearchMatch] {
        SettingsSearchIndex.matches(for: searchText)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
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
                        if !ScreenshotMode.isCapturingScreenshots {
                            Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Link("ishare.itoolio.dev", destination: URL(string: "https://ishare.itoolio.dev")!)
                            .font(.caption)
                    }
                    .padding(.bottom, 10)
                }
        } detail: {
            ScrollViewReader { proxy in
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
                .id(selection ?? .general)
                .settingsPaneStyle()
                .onChange(of: navigator.anchorRequest) { _, request in
                    guard let request else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        scroll(to: request.anchor, with: proxy)
                    }
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
            scheduleReveal()
        }
        .onAppear(perform: applyRequestedPane)
        .onChange(of: navigator.pane) { applyRequestedPane() }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(matches, id: \.pane) { match in
                    Button {
                        select(match)
                    } label: {
                        SettingsPaneRow(pane: match.pane, keyword: match.keyword, isSearching: !searchText.isEmpty, isSelected: match.pane == selection)
                    }
                    .buttonStyle(SettingsSidebarButtonStyle(isSelected: match.pane == selection))
                    .accessibilityAddTraits(match.pane == selection ? .isSelected : [])
                    .accessibilityIdentifier("settings.pane.\(match.pane.rawValue)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .menuAppearance(appliesToWindow: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.sidebar")
    }

    private func select(_ match: SettingsSearchMatch) {
        selection = match.pane
        guard !searchText.isEmpty, let anchor = match.anchor else { return }
        reveal(anchor)
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let panes = matches.map(\.pane)
        guard !panes.isEmpty else { return .handled }
        let index = selection.flatMap(panes.firstIndex(of:)) ?? 0
        selection = panes[min(max(index + offset, 0), panes.count - 1)]
        return .handled
    }

    private func scheduleReveal() {
        revealTask?.cancel()
        guard !searchText.isEmpty else { return }
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let anchor = matches.first(where: { $0.pane == selection })?.anchor else { return }
            reveal(anchor)
        }
    }

    private func reveal(_ anchor: String) {
        navigator.reveal(anchor)
    }

    private func scroll(to anchor: String, with proxy: ScrollViewProxy) {
        withMotionAnimation(.snappy(duration: 0.35)) {
            proxy.scrollTo(anchor, anchor: .center)
        }
        navigator.highlight(anchor)
    }

    private func applyRequestedPane() {
        guard let pane = navigator.pane else { return }
        searchText = ""
        selection = pane
        navigator.pane = nil
    }
}
