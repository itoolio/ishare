import SwiftUI

struct CommandPaletteView: View {
    let onClose: () -> Void
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var commands: [AppCommand] = []
    @FocusState private var isFieldFocused: Bool
    @Environment(\.menuContrast) private var contrast

    private var matches: [AppCommandMatch] {
        AppCommandRegistry.matches(for: query, in: commands)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            results
            Text("↑↓ to choose · ↩ to run · esc to close".localized())
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear {
            commands = AppCommand.all()
            selectedIndex = 0
            isFieldFocused = true
        }
        .onChange(of: query) { selectedIndex = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu.palette")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search actions".localized(), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFieldFocused)
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.return) { runSelection() }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .accessibilityIdentifier("menu.palette.search")
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close".localized())
            .accessibilityIdentifier("menu.palette.close")
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(contrast.fillOpacity)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.menuAccent.opacity(0.7), lineWidth: 1))
    }

    private var results: some View {
        let matches = matches
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                        CommandPaletteRow(command: match.command, isSelected: index == selectedIndex) {
                            run(match.command)
                        }
                        .id(match.id)
                    }
                }
            }
            .frame(height: 300)
            .overlay {
                if matches.isEmpty {
                    Text("No Matching Actions".localized())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: selectedIndex) { _, index in
                guard matches.indices.contains(index) else { return }
                proxy.scrollTo(matches[index].id)
            }
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let count = matches.count
        guard count > 0 else { return .handled }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
        return .handled
    }

    private func runSelection() -> KeyPress.Result {
        let matches = matches
        guard matches.indices.contains(selectedIndex) else { return .handled }
        run(matches[selectedIndex].command)
        return .handled
    }

    private func run(_ command: AppCommand) {
        onClose()
        command.perform()
    }
}

private struct CommandPaletteRow: View {
    let command: AppCommand
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: command.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                Text(command.title.localized())
                    .font(.system(size: 12, weight: Font.Weight.medium.emphasized(contrast)))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.menuAccent : Color.primary.opacity(isHovered ? contrast.fillOpacity : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("menu.palette.\(command.id)")
    }
}
