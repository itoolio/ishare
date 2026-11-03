import AppKit
import Defaults
import SwiftUI

struct ScriptHookSection: View {
    @Default(.scriptHookPath) private var scriptPath
    @Default(.scriptHookAfterCapture) private var afterCapture
    @Default(.scriptHookAfterUpload) private var afterUpload
    @State private var lastResult: String?

    var body: some View {
        Section {
            LabeledContent("Script".localized()) {
                HStack {
                    Text(scriptPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None".localized())
                        .foregroundStyle(scriptPath == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…".localized(), action: choose)
                    if scriptPath != nil {
                        Button("Remove".localized()) { scriptPath = nil }
                    }
                }
            }
            Toggle("Run after each capture and recording".localized(), isOn: $afterCapture)
                .disabled(scriptPath == nil)
            Toggle("Run after each upload".localized(), isOn: $afterUpload)
                .disabled(scriptPath == nil)
            HStack {
                Button("Test Script".localized(), action: test)
                    .disabled(scriptPath == nil)
                if let lastResult {
                    Text(lastResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Script Hook".localized())
                .settingsEntry(NewerSettingsSearch.scriptHook)
        } footer: {
            Text(
                "ishare runs the script with the event (capture, recording or upload), the file path and the link as arguments, and as ISHARE_EVENT, ISHARE_FILE and ISHARE_LINK. Scripts that aren’t executable run with zsh. A script is stopped after a minute."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a script to run after captures and uploads".localized()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scriptPath = url.path
    }

    private func test() {
        guard let scriptPath else { return }
        lastResult = "Running…".localized()
        Task {
            let status = await ScriptHooks.run(script: scriptPath, event: .upload, file: "/tmp/ishare-test.png", link: "https://example.com/ishare-test.png")
            lastResult = status.map { String(format: "Exited with status %d".localized(), $0) } ?? "The script couldn’t start".localized()
        }
    }
}
