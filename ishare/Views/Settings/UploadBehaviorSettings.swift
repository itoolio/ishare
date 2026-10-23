import Defaults
import SwiftUI

struct UploadBehaviorSettings: View {
    @Default(.copyURLAfterUpload) var copyURLAfterUpload
    @Default(.openURLAfterUpload) var openURLAfterUpload
    @Default(.copyImageToClipboard) var copyImageToClipboard
    @Default(.additionalUploadDestinations) var additionalUploadDestinations
    @Default(.destinationChooserModifier) var destinationChooserModifier
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.savedLocalUploaders) var savedLocalUploaders

    private var destinations: [(title: String, destination: UploadDestination)] {
        [("Imgur", UploadDestination.builtIn(.IMGUR))] + CustomUploader.allCases.map { ($0.name, UploadDestination.custom($0.id)) }
    }

    var body: some View {
        Section {
            Toggle("Copy URL after upload".localized(), isOn: $copyURLAfterUpload)
            if copyURLAfterUpload, copyImageToClipboard {
                Text("The image is copied instead because “Copy image to clipboard instead of URL” is on.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle("Open URL in browser after upload".localized(), isOn: $openURLAfterUpload)
            Picker("Choose destination while holding".localized(), selection: $destinationChooserModifier) {
                Text("Off".localized()).tag(ForceUploadModifier?.none)
                ForEach(ForceUploadModifier.allCases) { modifier in
                    Text(modifier.rawValue).tag(ForceUploadModifier?.some(modifier))
                }
            }
            Text("Hold this key when a capture starts or a recording stops to pick the uploader for it.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("After Upload".localized())
        }
        Section {
            ForEach(destinations, id: \.destination) { entry in
                Toggle(entry.title, isOn: binding(for: entry.destination))
            }
        } header: {
            Text("Also upload to".localized())
        } footer: {
            Text("Every upload also goes to these destinations. The URL from your active uploader is the one that gets copied.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for destination: UploadDestination) -> Binding<Bool> {
        Binding {
            additionalUploadDestinations.contains(destination)
        } set: { enabled in
            additionalUploadDestinations.removeAll { $0 == destination }
            if enabled {
                additionalUploadDestinations.append(destination)
            }
        }
    }
}
