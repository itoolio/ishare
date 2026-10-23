import AppKit
import Defaults
import SwiftUI

enum ProfileOverride: Hashable, CaseIterable, Identifiable {
    case inherit
    case on
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .inherit: "Default"
        case .on: "On"
        case .off: "Off"
        }
    }

    init(_ value: Bool?) {
        switch value {
        case .none: self = .inherit
        case .some(true): self = .on
        case .some(false): self = .off
        }
    }

    var value: Bool? {
        switch self {
        case .inherit: nil
        case .on: true
        case .off: false
        }
    }
}

struct ProfileCandidateApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    var id: String { bundleIdentifier }

    @MainActor static func running(excluding profiles: [CaptureProfile]) -> [ProfileCandidateApp] {
        let taken = Set(profiles.map { $0.bundleIdentifier.lowercased() })
        let ownBundleID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> ProfileCandidateApp? in
                guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID,
                      !taken.contains(bundleID.lowercased()), seen.insert(bundleID).inserted
                else { return nil }
                return ProfileCandidateApp(bundleIdentifier: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
struct CaptureProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @Default(.captureProfiles) var profiles

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("App Profiles".localized())
                    .font(.title)
                Text("Settings that apply when you capture a window of these apps, or while they are frontmost.".localized())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            Form {
                if profiles.isEmpty {
                    Text("No profiles yet".localized())
                        .foregroundStyle(.secondary)
                }
                ForEach($profiles) { $profile in
                    CaptureProfileSection(profile: $profile) {
                        profiles.removeAll { $0.id == profile.id }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Menu("Add Profile".localized()) {
                    let candidates = ProfileCandidateApp.running(excluding: profiles)
                    if candidates.isEmpty {
                        Text("No other apps are running".localized())
                    }
                    ForEach(candidates) { app in
                        Button(app.name) {
                            profiles.append(CaptureProfile(bundleIdentifier: app.bundleIdentifier, appName: app.name))
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Close".localized()) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }
}

private struct CaptureProfileSection: View {
    @Binding var profile: CaptureProfile
    let onDelete: () -> Void

    var body: some View {
        Section {
            Toggle("Enabled".localized(), isOn: $profile.isEnabled)
            overridePicker("Add a background".localized(), value: $profile.addsBackground)
            overridePicker("Blur private apps".localized(), value: $profile.blursPrivateApps)
            overridePicker("Include window shadow".localized(), value: $profile.includesWindowShadow)
            LabeledContent("File prefix:".localized()) {
                TextField("", text: Binding(
                    get: { profile.fileNamePrefix ?? "" },
                    set: { profile.fileNamePrefix = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Default".localized()))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            }
        } header: {
            HStack {
                Text(profile.appName)
                Text(profile.bundleIdentifier)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove Profile".localized())
            }
        }
    }

    private func overridePicker(_ title: String, value: Binding<Bool?>) -> some View {
        Picker(title, selection: Binding(
            get: { ProfileOverride(value.wrappedValue) },
            set: { value.wrappedValue = $0.value }
        )) {
            ForEach(ProfileOverride.allCases) { Text($0.title.localized()).tag($0) }
        }
    }
}
