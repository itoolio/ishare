import SwiftUI

extension UploaderEditorView {
    @ViewBuilder
    var customSections: some View {
        Section("Request".localized()) {
            TextField("Request URL*".localized(), text: $requestURL, prompt: Text("https://example.com/upload"))
            Picker("Method".localized(), selection: $requestMethod) {
                ForEach(UploadRequestMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Body".localized(), selection: $bodyType) {
                Text("Multipart form data".localized()).tag(RequestBodyType.multipartFormData)
                Text("Binary".localized()).tag(RequestBodyType.binary)
            }
            if bodyType == .multipartFormData {
                TextField("File Form Name".localized(), text: $fileFormName, prompt: Text("file"))
            }
        }
        Section("Response".localized()) {
            TextField("Response URL*".localized(), text: $responseURL, prompt: Text("{{data.url}}"))
            TextField("Deletion URL".localized(), text: $deletionURL, prompt: Text("{{data.deleteUrl}}"))
            Picker("Deletion method".localized(), selection: $deleteMethod) {
                Text("GET").tag(DeleteRequestType.get)
                Text("DELETE").tag(DeleteRequestType.delete)
            }
            Text("Use {{path.to.value}} to insert values from the JSON response, or {{response}} for a plain-text response.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        EntrySection(title: "Headers", entries: $headers)
        if bodyType == .multipartFormData {
            EntrySection(title: "Form Data", entries: $formData)
        }
        LinkOptionsSpecSection(draft: $linkDraft, allowsForm: bodyType == .multipartFormData)
        if let spec = linkDraft.spec {
            LinkOptionDefaultsSection(spec: spec, preferences: $linkPreferences, password: $defaultLinkPassword)
        }
    }
}
