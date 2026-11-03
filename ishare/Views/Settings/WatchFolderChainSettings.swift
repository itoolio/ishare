import Defaults
import ishareCore
import SwiftUI

struct WatchFolderChainSettings: View {
    @Default(.watchFolderActions) private var actions

    var body: some View {
        Section {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                WatchFolderActionRow(
                    action: Binding(get: { actions[safe: index] ?? action }, set: { if actions.indices.contains(index) { actions[index] = $0 } }),
                    canMoveUp: index > 0,
                    canMoveDown: index < actions.count - 1,
                    move: { offset in move(from: index, by: offset) },
                    remove: { actions.remove(at: index) }
                )
            }
            Menu("Add Step".localized()) {
                ForEach(WatchFolderAction.Kind.allCases, id: \.self) { kind in
                    Button(kind.title) { actions.append(WatchFolderAction(kind: kind)) }
                }
            }
            ForEach(WatchFolderChain.issues(in: actions), id: \.self) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        } header: {
            Text("Steps for New Files".localized())
        } footer: {
            Text("Each new file runs through these steps in order. Rename templates can use {{date}}, {{time}}, {{counter}} and {{name}}.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard actions.indices.contains(index), actions.indices.contains(target) else { return }
        actions.swapAt(index, target)
    }
}

private struct WatchFolderActionRow: View {
    @Binding var action: WatchFolderAction
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(action.kind.title)
            Spacer()
            options
            Button {
                move(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            .accessibilityLabel("Move Up".localized())
            Button {
                move(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
            .accessibilityLabel("Move Down".localized())
            Button(role: .destructive) {
                remove()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove Step".localized())
        }
    }

    @ViewBuilder
    private var options: some View {
        switch action.kind {
        case .rename:
            TextField("Template".localized(), text: $action.template)
                .frame(maxWidth: 200)
        case .convert:
            Picker("Format".localized(), selection: $action.format) {
                ForEach(WatchFolderChain.convertibleFormats, id: \.self) { Text($0.uppercased()).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case .upload:
            TextField("Default uploader".localized(), text: Binding(get: { action.uploader ?? "" }, set: { action.uploader = $0.isEmpty ? nil : $0 }))
                .frame(maxWidth: 180)
        case .moveToFolder:
            Button(action.folderPath.map { NSString(string: $0).abbreviatingWithTildeInPath } ?? "Choose Folder…".localized()) { chooseFolder() }
        default:
            EmptyView()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        Task { @MainActor in
            guard await panel.beginAsyncModal() == .OK, let url = panel.url else { return }
            action.folderPath = url.path(percentEncoded: false)
            action.folderBookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }
}

extension WatchFolderAction.Kind {
    var title: String {
        switch self {
        case .rename: "Rename".localized()
        case .convert: "Convert".localized()
        case .optimize: "Optimize".localized()
        case .stripMetadata: "Remove Metadata".localized()
        case .upload: "Upload".localized()
        case .copyLink: "Copy Link".localized()
        case .moveToFolder: "Move to Folder".localized()
        case .moveToTrash: "Move to Trash".localized()
        }
    }
}

extension WatchFolderChainIssue {
    var message: String {
        switch self {
        case .empty: "Add at least one step".localized()
        case .copyLinkBeforeUpload: "Copy Link needs an Upload step before it".localized()
        case .stepAfterMove: "Moving the file must be the last step".localized()
        case .missingFolder: "Choose a folder for Move to Folder".localized()
        case .emptyTemplate: "Enter a rename template".localized()
        }
    }
}
