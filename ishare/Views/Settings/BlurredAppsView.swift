import Defaults
import SwiftUI

@MainActor
struct BlurredAppsView: View {
    @Environment(\.dismiss) private var dismiss
    @Default(.blurredBundleIdentifiers) var blurredBundleIdentifiers

    private struct AppEntry: Identifiable, Hashable {
        let bundleIdentifier: String
        let name: String
        var id: String { bundleIdentifier }
    }

    private var entries: [AppEntry] {
        let ownBundleID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var result: [AppEntry] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID, seen.insert(bundleID).inserted else { continue }
            result.append(AppEntry(bundleIdentifier: bundleID, name: app.localizedName ?? bundleID))
        }
        for bundleID in blurredBundleIdentifiers where seen.insert(bundleID).inserted {
            result.append(AppEntry(bundleIdentifier: bundleID, name: bundleID))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack {
            Text("Select apps to blur".localized())
                .font(.title)

            Text("Windows of these apps are blurred in screenshots.".localized())
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(entries) { entry in
                        Toggle(isOn: binding(for: entry.bundleIdentifier)) {
                            Text(entry.name)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Button("Close".localized()) {
                dismiss()
            }
            .padding(.bottom)
        }
        .padding()
    }

    private func binding(for bundleIdentifier: String) -> Binding<Bool> {
        Binding(
            get: { blurredBundleIdentifiers.contains(bundleIdentifier) },
            set: { isBlurred in
                if isBlurred {
                    if !blurredBundleIdentifiers.contains(bundleIdentifier) {
                        blurredBundleIdentifiers.append(bundleIdentifier)
                    }
                } else {
                    blurredBundleIdentifiers.removeAll { $0 == bundleIdentifier }
                }
            }
        )
    }
}
