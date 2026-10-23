import AppKit
import Defaults
import SwiftUI

enum OnboardingTrial: String, CaseIterable, Codable, Sendable {
    case capture
    case editor
    case palette
}

extension OnboardingStep {
    var trial: OnboardingTrial? {
        switch self {
        case .tryCapture: .capture
        case .tryEditor: .editor
        case .tryPalette: .palette
        default: nil
        }
    }

    static func resumed(from rawValue: Int) -> OnboardingStep {
        OnboardingStep(rawValue: rawValue) ?? allCases.first ?? .permission
    }
}

@MainActor
final class OnboardingTrialModel: ObservableObject {
    @Published private(set) var captureURL: URL?
    @Published private(set) var preview: NSImage?
    @Published private(set) var isCapturing = false
    @Published private(set) var isEditing = false
    @Published var showsPalette = false
    @Published private(set) var completed: Set<OnboardingTrial>

    init(completed: Set<String> = Defaults[.onboardingTrials]) {
        self.completed = Set(completed.compactMap(OnboardingTrial.init(rawValue:)))
    }

    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "ishare-onboarding", directoryHint: .isDirectory)
    }

    func isCompleted(_ trial: OnboardingTrial) -> Bool {
        completed.contains(trial)
    }

    func complete(_ trial: OnboardingTrial) {
        guard completed.insert(trial).inserted else { return }
        Defaults[.onboardingTrials] = Set(completed.map(\.rawValue))
    }

    func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        let options = CaptureOptions(resultHandler: { [weak self] url in
            self?.receive(url)
        })
        await CaptureSession.captureImage(.REGION, options: options)
        isCapturing = false
        NSApp.activate(ignoringOtherApps: true)
    }

    func receive(_ url: URL) {
        let destination = Self.directory.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: url, to: destination)
            show(destination)
        } catch {
            show(url)
        }
        complete(.capture)
    }

    func openEditor() async {
        guard !isEditing, let url = captureURL ?? sampleCapture() else { return }
        isEditing = true
        defer { isEditing = false }
        if case let .saved(saved) = await ImageEditor.edit(fileURL: url) {
            show(saved)
            complete(.editor)
        }
    }

    func closePalette() {
        showsPalette = false
        complete(.palette)
    }

    private func show(_ url: URL) {
        captureURL = url
        preview = NSImage(contentsOf: url)
    }

    private func sampleCapture() -> URL? {
        guard let image = ScreenshotMode.sampleImage(size: CGSize(width: 1200, height: 750), hue: 0.72, title: "ishare") else { return nil }
        let url = Self.directory.appending(path: "sample.png")
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try ImageEncoder.write(image, as: .PNG, to: url)
        } catch {
            return nil
        }
        show(url)
        return url
    }
}

struct OnboardingTryCaptureStep: View {
    @ObservedObject var model: OnboardingTrialModel

    var body: some View {
        OnboardingTryItArea(isDone: model.isCompleted(.capture)) {
            OnboardingCapturePreview(model: model, placeholder: "rectangle.dashed")
        } actions: {
            Button {
                Task { @MainActor in await model.capture() }
            } label: {
                Label(model.captureURL == nil ? "Capture a Region".localized() : "Capture Again".localized(), systemImage: "rectangle.dashed")
            }
            .disabled(model.isCapturing)
            .accessibilityIdentifier("onboarding.try.capture")
        } caption: {
            Text("Drag over any part of the screen. The capture appears here and is not saved or uploaded.".localized())
        }
    }
}

struct OnboardingTryEditorStep: View {
    @ObservedObject var model: OnboardingTrialModel

    var body: some View {
        OnboardingTryItArea(isDone: model.isCompleted(.editor)) {
            OnboardingCapturePreview(model: model, placeholder: "pencil.and.scribble")
        } actions: {
            Button {
                Task { @MainActor in await model.openEditor() }
            } label: {
                Label("Open in Editor".localized(), systemImage: "pencil.and.scribble")
            }
            .disabled(model.isEditing)
            .accessibilityIdentifier("onboarding.try.editor")
        } caption: {
            Text(
                model.captureURL == nil
                    ? "No capture yet, so a sample image opens. Add an arrow or some text, then click Done.".localized()
                    : "Add an arrow or some text, then click Done to bring it back here.".localized())
        }
    }
}

struct OnboardingTryPaletteStep: View {
    @ObservedObject var model: OnboardingTrialModel
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if model.showsPalette {
                CommandPaletteView(onClose: model.closePalette)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.menuAccent.opacity(0.5), lineWidth: 1))
                    .menuAppearance(appliesToWindow: false)
                    .accessibilityIdentifier("onboarding.try.palette")
            } else {
                OnboardingTryItArea(isDone: model.isCompleted(.palette)) {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            OnboardingKeyCap(text: "⌘")
                            OnboardingKeyCap(text: "K")
                        }
                        Text("Press ⌘K to search every action".localized())
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } actions: {
                    Button {
                        model.showsPalette = true
                    } label: {
                        Label("Show the Palette".localized(), systemImage: "command")
                    }
                    .accessibilityIdentifier("onboarding.try.paletteButton")
                } caption: {
                    Text("The same palette opens from the menu or with its global shortcut.".localized())
                }
            }
        }
        .focusable(!model.showsPalette)
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command), press.characters.lowercased() == "k" else { return .ignored }
            if model.showsPalette {
                model.closePalette()
            } else {
                model.showsPalette = true
            }
            return .handled
        }
        .onAppear { isFocused = true }
    }
}

private struct OnboardingKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

private struct OnboardingCapturePreview: View {
    @ObservedObject var model: OnboardingTrialModel
    let placeholder: String

    var body: some View {
        ZStack {
            if let preview = model.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                    .padding(10)
                    .accessibilityLabel("Your capture".localized())
                    .accessibilityIdentifier("onboarding.try.preview")
            } else {
                Image(systemName: placeholder)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.menuAccent.opacity(0.6))
            }
            if model.isCapturing || model.isEditing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingTryItArea<Content: View, Actions: View, Caption: View>: View {
    let isDone: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @ViewBuilder var caption: Caption

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(
                            Color.menuAccent.opacity(0.45)))
                Label(isDone ? "Done".localized() : "Try It".localized(), systemImage: isDone ? "checkmark.circle.fill" : "hand.tap")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isDone ? Color.green : Color.menuAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.background))
                    .padding(8)
                    .accessibilityIdentifier("onboarding.try.status")
            }
            actions
                .controlSize(.large)
            caption
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
