import Defaults
import SwiftUI

@MainActor
struct ExcludedAppsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Default(.ignoredBundleIdentifiers) var ignoredBundleIdentifiers

    var body: some View {
        VStack {
            Text("Select apps to exclude")
                .font(.title)

            Divider()

            ScrollView {
                ForEach(NSWorkspace.shared.runningApplications.sorted { $0.localizedName ?? "" < $1.localizedName ?? "" }.filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }, id: \.self) { app in
                    Toggle(isOn: Binding(
                        get: {
                            ignoredBundleIdentifiers.contains(app.bundleIdentifier ?? "")
                        },
                        set: { newValue in
                            if newValue {
                                ignoredBundleIdentifiers.append(app.bundleIdentifier ?? "")
                            } else {
                                ignoredBundleIdentifiers.removeAll { $0 == app.bundleIdentifier }
                            }
                        }
                    )) {
                        Text(app.localizedName ?? app.bundleIdentifier ?? "unknown")
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Spacer()

            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.bottom)
        }
        .padding()
    }
}
