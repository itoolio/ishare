import Defaults
import SwiftUI

struct WebhookSettings: View {
    @Default(.uploadWebhooks) var webhooks
    @State private var editing: UploadWebhook?

    var body: some View {
        Section {
            if webhooks.isEmpty {
                Text("No webhooks yet".localized())
                    .foregroundStyle(.secondary)
            }
            ForEach($webhooks) { $webhook in
                HStack {
                    Toggle(isOn: $webhook.enabled) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(webhook.displayName)
                            Text("\(webhook.style.titleKey.localized()) · \(webhook.url)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Button {
                        editing = webhook
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit Webhook".localized())
                    Button {
                        remove(webhook)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete Webhook".localized())
                }
            }
            Button {
                editing = UploadWebhook()
            } label: {
                Label("Add Webhook".localized(), systemImage: "plus")
            }
            .settingsEntry(Self.entry)
            Text("After every successful upload ishare sends a POST request with the link, deletion link, file name, size, type, uploader, time and alt text. With a secret, the body is signed with HMAC-SHA256 in the X-ishare-Signature header. Failed deliveries are retried in the background and never delay the upload.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Webhooks".localized())
        }
        .sheet(item: $editing) { webhook in
            WebhookEditor(webhook: webhook) { saved in
                save(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
            .frame(width: 480, height: 400)
        }
    }

    private func save(_ webhook: UploadWebhook) {
        let stored = WebhookSecrets.storing(webhook)
        if let index = webhooks.firstIndex(where: { $0.id == stored.id }) {
            webhooks[index] = stored
        } else {
            webhooks.append(stored)
        }
    }

    private func remove(_ webhook: UploadWebhook) {
        WebhookSecrets.remove(webhook)
        webhooks.removeAll { $0.id == webhook.id }
    }
}

extension WebhookSettings {
    static let entry = SettingsSearchEntry(
        "Webhooks", pane: .uploaders, keywords: ["Webhook", "Slack", "Discord", "Notify", "HMAC", "Signature", "POST"],
        anchor: "uploaders.webhooks"
    )
}

struct WebhookEditor: View {
    let webhook: UploadWebhook
    let onSave: (UploadWebhook) -> Void
    let onCancel: () -> Void

    @State private var draft = UploadWebhook()
    @State private var secret = ""
    @State private var testResult: WebhookDelivery?
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name".localized(), text: $draft.name, prompt: Text("Team channel"))
                    TextField("URL".localized(), text: $draft.url, prompt: Text("https://example.com/hooks/ishare"))
                    Picker("Payload".localized(), selection: $draft.style) {
                        ForEach(WebhookPayloadStyle.allCases) { style in
                            Text(style.titleKey.localized()).tag(style)
                        }
                    }
                    SecureField("Signing secret".localized(), text: $secret)
                    Text("Use Slack or Discord for their incoming webhook URLs. The ishare JSON payload suits your own server.".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Button("Send Test".localized(), action: sendTest)
                            .disabled(built.endpoint == nil || isTesting)
                        if isTesting {
                            ProgressView().controlSize(.small)
                        }
                        Spacer()
                    }
                    if let testResult {
                        switch testResult {
                        case let .delivered(status):
                            Label(String(format: "Delivered (HTTP %d)".localized(), status), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case let .failed(detail, _):
                            Label(detail, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel".localized(), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save".localized()) { onSave(built) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(built.endpoint == nil)
            }
            .padding(14)
        }
        .onAppear {
            draft = webhook
            secret = WebhookSecrets.secret(for: webhook) ?? ""
        }
    }

    private var built: UploadWebhook {
        var copy = draft
        copy.url = draft.url.trimmingCharacters(in: .whitespaces)
        copy.secret = secret.isEmpty ? nil : secret
        return copy
    }

    private func sendTest() {
        isTesting = true
        testResult = nil
        let target = built
        Task { @MainActor in
            testResult = await WebhookDispatcher.sendTest(to: target)
            isTesting = false
        }
    }
}
