import SwiftUI

extension UploaderEditorView {
    @ViewBuilder
    var s3Sections: some View {
        Section("Bucket".localized()) {
            TextField("Endpoint".localized(), text: $endpoint, prompt: Text("https://s3.us-east-1.amazonaws.com"))
            TextField("Region".localized(), text: $region, prompt: Text("us-east-1"))
            TextField("Bucket".localized(), text: $bucket)
            Toggle("Path-style URLs".localized(), isOn: $pathStyle)
        }
        Section("Credentials".localized()) {
            TextField("Access key ID".localized(), text: $accessKeyId)
            SecureField("Secret access key".localized(), text: $secretAccessKey)
        }
        Section("Objects".localized()) {
            TextField("Key template".localized(), text: $keyTemplate)
            TextField("ACL".localized(), text: $acl, prompt: Text("public-read"))
            TextField("Public URL".localized(), text: $publicURL, prompt: Text("https://cdn.example.com/{{key}}"))
                .disabled(expiringLinks)
            Text("Key placeholders: {{filename}}, {{name}}, {{ext}}, {{uuid}}, {{random}}, {{timestamp}}, {{date}}. Public URL placeholders: {{key}}, {{bucket}}, {{region}}, {{host}}, {{endpoint}}.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle("Expiring links".localized(), isOn: $expiringLinks)
            if expiringLinks {
                LabeledContent("Links expire after".localized()) {
                    HStack {
                        TextField("", value: $presignedExpiry, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("seconds".localized())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("ishare returns a signed link to the private object instead of the public URL. Links can last up to 7 days (604800 seconds).".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
