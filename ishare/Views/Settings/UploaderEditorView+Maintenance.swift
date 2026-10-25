import ishareCore
import SwiftUI

struct LinkRewriteDraft: Equatable {
    enum Mode: String, CaseIterable, Identifiable {
        case rules
        case template

        var id: Self { self }
    }

    var enabled = false
    var mode: Mode = .rules
    var host = ""
    var scheme = ""
    var pathPrefix = ""
    var stripQuery = false
    var template = ""
    var rewritesDeletionURL = false

    static let sampleURL = URL(string: "https://uploads.example.com/files/a1b2c3.png?token=abc")!

    init() {}

    init(rule: LinkRewrite?) {
        guard let rule else { return }
        enabled = true
        mode = rule.trimmedTemplate == nil ? .rules : .template
        host = rule.host ?? ""
        scheme = rule.trimmedScheme ?? ""
        pathPrefix = rule.pathPrefix ?? ""
        stripQuery = rule.stripQuery ?? false
        template = rule.template ?? ""
        rewritesDeletionURL = rule.rewritesDeletionURL ?? false
    }

    var rule: LinkRewrite? {
        guard enabled else { return nil }
        let deletion: Bool? = rewritesDeletionURL ? true : nil
        switch mode {
        case .template:
            return LinkRewrite(template: template.trimmingCharacters(in: .whitespaces), rewritesDeletionURL: deletion)
        case .rules:
            return LinkRewrite(
                host: Self.nonEmpty(host), scheme: Self.nonEmpty(scheme), pathPrefix: Self.nonEmpty(pathPrefix), stripQuery: stripQuery ? true : nil,
                rewritesDeletionURL: deletion
            )
        }
    }

    func preview(of url: URL?) -> (original: String, rewritten: String?) {
        let source = url ?? Self.sampleURL
        guard let rule, rule.issues.isEmpty else { return (source.absoluteString, nil) }
        return (source.absoluteString, rule.apply(to: source)?.absoluteString)
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct LinkRewriteSection: View {
    @Binding var draft: LinkRewriteDraft
    let lastLink: URL?

    var body: some View {
        Section {
            Toggle("Rewrite returned links".localized(), isOn: $draft.enabled)
            if draft.enabled {
                Picker("Rewrite with".localized(), selection: $draft.mode) {
                    Text("Rules".localized()).tag(LinkRewriteDraft.Mode.rules)
                    Text("Template".localized()).tag(LinkRewriteDraft.Mode.template)
                }
                .pickerStyle(.segmented)
                switch draft.mode {
                case .rules:
                    TextField("Host".localized(), text: $draft.host, prompt: Text(verbatim: "cdn.example.com"))
                    Picker("Scheme".localized(), selection: $draft.scheme) {
                        Text("Keep".localized()).tag("")
                        Text(verbatim: "https").tag("https")
                        Text(verbatim: "http").tag("http")
                    }
                    TextField("Path prefix".localized(), text: $draft.pathPrefix, prompt: Text(verbatim: "/i"))
                    Toggle("Remove the query string".localized(), isOn: $draft.stripQuery)
                case .template:
                    TextField("Link template".localized(), text: $draft.template, prompt: Text(verbatim: "https://cdn.example.com/{{path}}"))
                    Text("Placeholders:".localized() + " " + LinkRewrite.placeholders.map { "{{\($0)}}" }.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Toggle("Also rewrite the deletion URL".localized(), isOn: $draft.rewritesDeletionURL)
                previewRows
            }
        } header: {
            Text("Link Rewriting".localized())
        }
    }

    @ViewBuilder private var previewRows: some View {
        let preview = draft.preview(of: lastLink)
        LabeledContent("Returned link".localized()) {
            Text(verbatim: preview.original)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        LabeledContent("Rewritten link".localized()) {
            if let rewritten = preview.rewritten {
                Text(verbatim: rewritten)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } else {
                Text("Fix the rules to see a preview".localized())
                    .foregroundStyle(.orange)
            }
        }
        Text(
            lastLink == nil
                ? "The preview uses an example link until this uploader returns one.".localized()
                : "The preview uses the last link this uploader returned.".localized()
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct AutoDeleteSection: View {
    @Binding var preset: AutoDeletePreset
    @Binding var customDays: Int
    let canDelete: Bool

    var body: some View {
        Section {
            Picker("Delete uploads from the server".localized(), selection: $preset) {
                ForEach(AutoDeletePreset.allCases) { preset in
                    Text(preset.titleKey.localized()).tag(preset)
                }
            }
            if preset == .custom {
                Stepper(value: $customDays, in: 1 ... UploadExpiry.maximumDays) {
                    Text(String(format: "After %d days".localized(), customDays))
                }
            }
            Text(
                canDelete
                    ? "ishare deletes uploads once they're older than this, checks daily and after your Mac wakes, and never deletes uploads you mark “Keep Forever” in your history."
                        .localized()
                    : "Add a deletion URL so ishare can delete uploads automatically.".localized()
            )
            .font(.footnote)
            .foregroundStyle(canDelete ? Color.secondary : Color.orange)
        } header: {
            Text("Auto-Delete".localized())
        }
    }
}

extension UploaderEditorView {
    var autoDeleteDays: Int? {
        preset(autoDeletePreset, customDays: autoDeleteCustomDays)
    }

    func preset(_ preset: AutoDeletePreset, customDays: Int) -> Int? {
        preset == .custom ? customDays : preset.days
    }

    func loadMaintenance(from uploader: CustomUploader) {
        linkRewriteDraft = LinkRewriteDraft(rule: uploader.linkRewrite)
        autoDeletePreset = AutoDeletePreset(days: uploader.autoDeleteAfterDays)
        if autoDeletePreset == .custom, let days = uploader.autoDeleteAfterDays {
            autoDeleteCustomDays = days
        }
    }

    func applyMaintenance(to uploader: inout CustomUploader) {
        uploader.linkRewrite = kind == .photos ? nil : linkRewriteDraft.rule
        uploader.autoDeleteAfterDays = kind.supportsServerDeletion ? autoDeleteDays : nil
    }

    @ViewBuilder var maintenanceSections: some View {
        if kind != .photos {
            LinkRewriteSection(draft: $linkRewriteDraft, lastLink: LinkRewriting.lastLink(for: id))
        }
        if kind.supportsServerDeletion {
            AutoDeleteSection(preset: $autoDeletePreset, customDays: $autoDeleteCustomDays, canDelete: build().supportsAutoDelete)
        }
    }
}
