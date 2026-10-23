import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct SettingsPaneRow: View {
    let pane: SettingsPane
    let keyword: String?
    let isSearching: Bool
    var isSelected = false

    var body: some View {
        HStack(spacing: 9) {
            SettingsIconTile(symbol: pane.symbol, tint: pane.tint, isSelected: isSelected)
            VStack(alignment: .leading, spacing: 1) {
                Text(pane.title.localized())
                    .font(.system(size: 13, weight: isSearching || isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                if let keyword {
                    Text(keyword.localized().trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                        .font(.caption)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct SettingsIconTile: View {
    let symbol: String
    let tint: Color
    var isSelected = false
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(tint.gradient)
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.white.opacity(isSelected ? 0.7 : 0.18), lineWidth: isSelected ? 1 : 0.5))
            .shadow(color: tint.opacity(isSelected ? 0 : 0.25), radius: 2, y: 1)
    }
}

struct SettingsSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarButtonBody(isSelected: isSelected, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct SettingsSidebarButtonBody<Content: View>: View {
    let isSelected: Bool
    let isPressed: Bool
    @ViewBuilder var content: Content
    @State private var isHovered = false
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.menuAccent : Color.primary.opacity(isHovered || isPressed ? contrast.fillOpacity : 0))
            )
            .overlay {
                if contrast.isHigh, !isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isHovered ? contrast.borderOpacity : 0), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct SettingsPaneStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(SettingsBackdrop())
            .tint(Color.menuAccent)
            .environment(\.defaultMinListRowHeight, 30)
    }
}

struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.menuAccent.opacity(colorScheme == .dark ? 0.10 : 0.06), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    func settingsPaneStyle() -> some View {
        modifier(SettingsPaneStyle())
    }

    func settingsAnchor(_ anchor: String) -> some View {
        modifier(SettingsAnchorModifier(anchor: anchor))
    }
}

private struct SettingsAnchorModifier: ViewModifier {
    let anchor: String
    @EnvironmentObject private var app: AppModel

    func body(content: Content) -> some View {
        let isHighlighted = app.settings.highlightedAnchor == anchor
        content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.menuAccent.opacity(isHighlighted ? 0.18 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.menuAccent.opacity(isHighlighted ? 0.8 : 0), lineWidth: 1.5))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.35), value: isHighlighted)
            .id(anchor)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
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
