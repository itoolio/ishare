import AppKit
import Defaults
import ishareCore
import SwiftUI

struct LocalAPISection: View {
    @Default(.localAPIEnabled) private var enabled
    @Default(.localAPIPort) private var port
    @Default(.localAPIToken) private var token

    var body: some View {
        Section {
            Toggle("Allow apps on this Mac to use ishare over HTTP".localized(), isOn: $enabled)
            if enabled {
                LabeledContent("Port".localized()) {
                    TextField("", value: $port, format: .number.grouping(.never))
                        .labelsHidden()
                        .frame(width: 80)
                }
                LabeledContent("Token".localized()) {
                    HStack {
                        Text(token.isEmpty ? "—" : String(token.prefix(8)) + "…")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button("Copy".localized()) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(token, forType: .string)
                        }
                        .disabled(token.isEmpty)
                        Button("New Token".localized()) { token = LocalAPIRequest.makeToken() }
                    }
                }
                Text(verbatim: "curl -H \"Authorization: Bearer …\" http://127.0.0.1:\(port)/v1/recent_uploads?limit=5")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Local API".localized())
                .settingsEntry(NewerSettingsSearch.localAPI)
        } footer: {
            Text(
                "Only reachable from this Mac, and only with the token. The endpoints match the MCP tools: GET or POST /v1/capture, /v1/capture_app, /v1/upload, /v1/list_uploaders, /v1/recent_uploads and /v1/record, with the same JSON answers as the command-line tool."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
