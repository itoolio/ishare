import AppKit
import ishareCore
import SwiftUI

struct LinkOptionsDraft: Equatable {
    var passwordEnabled = false
    var passwordField = "password"
    var passwordLocation: LinkOptionLocation = .form
    var passwordTemplate = ""
    var expiryEnabled = false
    var expiryField = "expires"
    var expiryLocation: LinkOptionLocation = .form
    var expiryFormat: LinkExpiryFormat = .seconds
    var expiryTemplate = ""

    init() {}

    init(spec: LinkOptionsSpec?) {
        if let password = spec?.password {
            passwordEnabled = true
            passwordField = password.field
            passwordLocation = password.location
            passwordTemplate = password.template ?? ""
        }
        if let expiry = spec?.expiry {
            expiryEnabled = true
            expiryField = expiry.field
            expiryLocation = expiry.location
            expiryFormat = expiry.format
            expiryTemplate = expiry.template ?? ""
        }
    }

    var spec: LinkOptionsSpec? {
        let password = passwordEnabled
            ? LinkPasswordField(field: passwordField.trimmingCharacters(in: .whitespaces), location: passwordLocation, template: Self.nonEmpty(passwordTemplate))
            : nil
        let expiry = expiryEnabled
            ? LinkExpiryField(
                field: expiryField.trimmingCharacters(in: .whitespaces), location: expiryLocation, format: expiryFormat,
                template: Self.nonEmpty(expiryTemplate)
            )
            : nil
        let spec = LinkOptionsSpec(password: password, expiry: expiry)
        return spec.isEmpty ? nil : spec
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension LinkOptionLocation {
    var titleKey: String {
        switch self {
        case .form: "Form field"
        case .header: "Header"
        case .query: "Query parameter"
        }
    }
}

extension LinkExpiryFormat {
    var titleKey: String {
        switch self {
        case .seconds: "Seconds from now"
        case .minutes: "Minutes from now"
        case .iso8601: "ISO 8601 date"
        case .timestamp: "Unix timestamp"
        }
    }
}

struct LinkOptionsSpecSection: View {
    @Binding var draft: LinkOptionsDraft
    let allowsForm: Bool

    var body: some View {
        Section {
            Toggle("Supports link passwords".localized(), isOn: $draft.passwordEnabled)
            if draft.passwordEnabled {
                TextField("Password field".localized(), text: $draft.passwordField, prompt: Text("password"))
                locationPicker(selection: $draft.passwordLocation)
                TextField("Value template".localized(), text: $draft.passwordTemplate, prompt: Text("{{value}}"))
            }
            Toggle("Supports expiring links".localized(), isOn: $draft.expiryEnabled)
            if draft.expiryEnabled {
                TextField("Expiry field".localized(), text: $draft.expiryField, prompt: Text("expires"))
                locationPicker(selection: $draft.expiryLocation)
                Picker("Format".localized(), selection: $draft.expiryFormat) {
                    ForEach(LinkExpiryFormat.allCases, id: \.self) { Text($0.titleKey.localized()).tag($0) }
                }
                TextField("Value template".localized(), text: $draft.expiryTemplate, prompt: Text("{{value}}"))
            }
            Text("ishare sends the password and expiry you choose for an upload in these fields. Use a value template such as date={{value}} when the service expects a prefix.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Link Options".localized())
        }
    }

    private func locationPicker(selection: Binding<LinkOptionLocation>) -> some View {
        Picker("Send as".localized(), selection: selection) {
            ForEach(LinkOptionLocation.allCases, id: \.self) { location in
                Text(location.titleKey.localized()).tag(location)
                    .disabled(location == .form && !allowsForm)
            }
        }
    }
}

struct LinkOptionDefaultsSection: View {
    let spec: LinkOptionsSpec
    @Binding var preferences: LinkOptionPreferences
    @Binding var password: String

    var body: some View {
        Section {
            if spec.password != nil {
                Toggle("Protect links with a password".localized(), isOn: $preferences.usesPassword)
                if preferences.usesPassword {
                    SecureField("Default password".localized(), text: $password)
                }
            }
            if spec.expiry != nil {
                Picker("Links expire".localized(), selection: $preferences.expiry) {
                    ForEach(LinkExpiryChoice.allCases) { Text($0.titleKey.localized()).tag($0) }
                }
            }
            Toggle("Ask every time".localized(), isOn: $preferences.asksEveryTime)
            Text("When Ask every time is on, ishare shows these options before each upload to this uploader. The default password is kept in your Keychain.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Per-upload Defaults".localized())
        }
    }
}

@MainActor
@Observable
final class LinkChoiceModel {
    let spec: LinkOptionsSpec
    var usesPassword: Bool
    var password: String
    var expiry: LinkExpiryChoice

    init(spec: LinkOptionsSpec, suggested: LinkChoice) {
        self.spec = spec
        usesPassword = !(suggested.password ?? "").isEmpty
        password = suggested.password ?? ""
        expiry = suggested.expiry.flatMap(LinkExpiryChoice.init(rawValue:)) ?? .never
    }

    var choice: LinkChoice {
        LinkChoice(
            password: spec.password != nil && usesPassword && !password.isEmpty ? password : nil,
            expiry: spec.expiry == nil ? nil : expiry.seconds
        )
    }
}

struct LinkChoiceForm: View {
    @Bindable var model: LinkChoiceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.spec.password != nil {
                Toggle("Protect with a password".localized(), isOn: $model.usesPassword)
                SecureField("Password".localized(), text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.usesPassword)
            }
            if model.spec.expiry != nil {
                Picker("Link expires".localized(), selection: $model.expiry) {
                    ForEach(LinkExpiryChoice.allCases) { Text($0.titleKey.localized()).tag($0) }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 300, alignment: .leading)
    }
}

@MainActor
enum LinkOptionsPrompt {
    static func ask(_ uploader: CustomUploader, _ suggested: LinkChoice) async -> LinkChoice? {
        guard let spec = uploader.linkOptions, !spec.isEmpty else { return suggested }
        let model = LinkChoiceModel(spec: spec, suggested: suggested)
        let alert = NSAlert()
        alert.messageText = String(format: "Upload to %@".localized(), uploader.name)
        alert.informativeText = "Choose the link options for this upload.".localized()
        alert.addButton(withTitle: "Upload".localized())
        alert.addButton(withTitle: "Cancel".localized())
        let hosting = NSHostingView(rootView: LinkChoiceForm(model: model))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        alert.accessoryView = hosting
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? model.choice : nil
    }
}
