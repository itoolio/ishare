import Defaults
import KeyboardShortcuts
import SettingsAccess
import SwiftUI
import UniformTypeIdentifiers

enum Onboarding {
    static let windowID = "onboarding"
    static let skipArgument = "-ishareSkipOnboarding"

    static func shouldPresent(hasCompleted: Bool, screenshotMode: Bool, arguments: [String], environment: [String: String] = [:]) -> Bool {
        !hasCompleted && !screenshotMode && !arguments.contains(skipArgument) && environment["XCTestConfigurationFilePath"] == nil
    }

    @MainActor static var shouldPresentAtLaunch: Bool {
        shouldPresent(
            hasCompleted: Defaults[.hasCompletedOnboarding],
            screenshotMode: ScreenshotMode.isActive,
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case permission
    case uploader
    case shortcuts
    case afterCapture

    var id: Self { self }

    var title: String {
        switch self {
        case .permission: "Allow Screen Recording"
        case .uploader: "Choose Where to Upload"
        case .shortcuts: "Capture from Anywhere"
        case .afterCapture: "After Every Capture"
        }
    }

    var subtitle: String {
        switch self {
        case .permission: "ishare needs screen recording access to take screenshots and recordings."
        case .uploader: "Use Imgur right away, import an .iscu file or set up your own server."
        case .shortcuts: "These shortcuts work in every app. Change them any time in Settings."
        case .afterCapture: "Pick what happens automatically once you take a screenshot or recording."
        }
    }

    var symbol: String {
        switch self {
        case .permission: "lock.shield"
        case .uploader: "icloud.and.arrow.up"
        case .shortcuts: "command"
        case .afterCapture: "wand.and.stars"
        }
    }
}

struct OnboardingView: View {
    @State private var step: OnboardingStep = .permission
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 32)
            Group {
                switch step {
                case .permission: OnboardingPermissionStep()
                case .uploader: OnboardingUploaderStep()
                case .shortcuts: OnboardingShortcutsStep()
                case .afterCapture: OnboardingAfterCaptureStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 18)
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 560, height: 480)
        .background(.background)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            Defaults[.hasCompletedOnboarding] = true
        }
        .accessibilityIdentifier("onboarding.window")
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: step.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.menuAccent.gradient))
            Text(step.title.localized())
                .font(.system(size: 22, weight: .bold))
            Text(step.subtitle.localized())
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Skip".localized()) { finish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.skip")
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { candidate in
                    Circle()
                        .fill(candidate == step ? Color.menuAccent : Color.primary.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                Button("Back".localized()) { withAnimation(.snappy) { step = previous } }
                    .accessibilityIdentifier("onboarding.back")
            }
            if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                Button("Continue".localized()) { withAnimation(.snappy) { step = next } }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.next")
            } else {
                Button("Get Started".localized()) { finish() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.done")
            }
        }
        .controlSize(.large)
    }

    private func finish() {
        Defaults[.hasCompletedOnboarding] = true
        dismiss()
    }
}

struct OnboardingPermissionStep: View {
    @State private var granted = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(spacing: 16) {
            OnboardingCard {
                HStack(spacing: 14) {
                    Image(systemName: granted ? "checkmark.seal.fill" : "rectangle.dashed.badge.record")
                        .font(.system(size: 24))
                        .foregroundStyle(granted ? Color.green : Color.menuAccent)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(granted ? "Screen recording is allowed".localized() : "Screen recording is not allowed yet".localized())
                            .font(.system(size: 13, weight: .semibold))
                        Text("Drag ishare into the Screen & System Audio Recording list, then turn it on.".localized())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !granted {
                        Button("Allow…".localized()) {
                            PermissionGuide.show(.screenRecording)
                        }
                        .accessibilityIdentifier("onboarding.permission.allow")
                    }
                }
            }
            Text("You may need to relaunch ishare after allowing access.".localized())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .task {
            while !Task.isCancelled {
                granted = CGPreflightScreenCaptureAccess()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct OnboardingUploaderStep: View {
    @Default(.uploadDestination) private var uploadDestination

    var body: some View {
        VStack(spacing: 10) {
            OnboardingChoice(
                symbol: "photo.on.rectangle",
                title: "Use Imgur",
                detail: "Free anonymous image hosting, ready to go.",
                isSelected: uploadDestination == .builtIn(.IMGUR),
                identifier: "onboarding.uploader.imgur"
            ) {
                Defaults[.uploadDestination] = .builtIn(.IMGUR)
                Defaults[.activeCustomUploader] = nil
                Defaults[.uploadType] = .IMGUR
            }
            OnboardingChoice(
                symbol: "doc.badge.arrow.up",
                title: "Import .iscu File…",
                detail: "Load a custom uploader shared by your server or a friend.",
                isSelected: isCustom,
                identifier: "onboarding.uploader.import"
            ) {
                importUploader()
            }
            SettingsLink {
                OnboardingChoiceLabel(
                    symbol: "server.rack",
                    title: "Set Up an Uploader…",
                    detail: "Configure your own server or S3-compatible storage in Settings.",
                    isSelected: false
                )
            } preAction: {
                SettingsNavigator.shared.pane = .uploaders
                NSApp.activate(ignoringOtherApps: true)
            } postAction: {}
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.uploader.settings")
        }
    }

    private var isCustom: Bool {
        if case .custom = uploadDestination { return true }
        return false
    }

    private func importUploader() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType("com.castdrian.ishare") ?? .json, .json]
        Task { @MainActor in
            if await panel.beginAsyncModal() == .OK, let url = panel.url {
                importIscu(url)
            }
        }
    }
}

struct OnboardingShortcutsStep: View {
    private let shortcuts: [(String, String, KeyboardShortcuts.Name)] = [
        ("rectangle.dashed", "Capture Region", .captureRegion),
        ("macwindow", "Capture Window", .captureWindow),
        ("display", "Capture Screen", .captureScreen),
        ("record.circle", "Record Screen", .recordScreen),
        ("menubar.rectangle", "Open Main Menu", .toggleMainMenu),
        ("clock.arrow.circlepath", "Open History Window", .openHistoryWindow),
    ]

    var body: some View {
        OnboardingCard {
            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Image(systemName: entry.0)
                            .frame(width: 22)
                            .foregroundStyle(Color.menuAccent)
                        Text(entry.1.localized())
                            .font(.system(size: 13))
                        Spacer()
                        Text(KeyboardShortcuts.getShortcut(for: entry.2)?.description ?? "Not set".localized())
                            .font(.system(size: 12, weight: .medium).monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                    }
                    .padding(.vertical, 7)
                    if index < shortcuts.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

struct OnboardingAfterCaptureStep: View {
    @Default(.copyToClipboard) private var copyToClipboard
    @Default(.saveToDisk) private var saveToDisk
    @Default(.openInFinder) private var openInFinder
    @Default(.uploadMedia) private var uploadMedia
    @Default(.openEditorAfterCapture) private var openEditorAfterCapture

    var body: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Copy to Clipboard".localized(), isOn: $copyToClipboard)
                Toggle("Save to Disk".localized(), isOn: $saveToDisk)
                    .onChange(of: saveToDisk) { _, saved in
                        if !saved { openInFinder = false }
                    }
                Toggle("Open in Finder".localized(), isOn: $openInFinder)
                    .disabled(!saveToDisk)
                Toggle("Upload Media".localized(), isOn: $uploadMedia)
                Toggle("Open Editor".localized(), isOn: $openEditorAfterCapture)
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct OnboardingChoiceLabel: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.menuAccent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? Color.menuAccent : Color.menuAccent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized())
                    .font(.system(size: 13, weight: .semibold))
                Text(detail.localized())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.menuAccent)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? Color.menuAccent : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1))
        .contentShape(Rectangle())
    }
}

struct OnboardingChoice: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OnboardingChoiceLabel(symbol: symbol, title: title, detail: detail, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
