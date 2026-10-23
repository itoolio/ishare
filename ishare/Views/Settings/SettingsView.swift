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
