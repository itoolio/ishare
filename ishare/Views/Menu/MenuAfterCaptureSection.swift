import Defaults
import SwiftUI

struct MenuAfterCaptureSection: View {
    @Default(.copyToClipboard) private var copyToClipboard
    @Default(.openInFinder) private var openInFinder
    @Default(.saveToDisk) private var saveToDisk
    @Default(.uploadMedia) private var uploadMedia
    @Default(.openEditorAfterCapture) private var openEditorAfterCapture
    @Default(.builtInShare) private var builtInShare
    @Default(.menuDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(Array(AfterCaptureStep.allCases.enumerated()), id: \.element) { index, step in
                    if index > 0, AfterCaptureStep.allCases[index - 1].group != step.group {
                        Divider()
                            .frame(height: 22)
                    }
                    chip(step)
                        .menuFocusRing(.chip(index), shape: .circle)
                }
            }
            if density == .comfortable {
                MenuSecondaryText(text: summary)
            }
        }
    }

    static func toggle(at index: Int) {
        guard let step = AfterCaptureStep.allCases[safe: index], step.dependsOn.map(\.isEnabled) ?? true else { return }
        step.isEnabled.toggle()
    }

    private var summary: String {
        _ = (openEditorAfterCapture, saveToDisk, copyToClipboard, openInFinder, builtInShare.airdrop, uploadMedia)
        return AfterCaptureStep.summary
    }

    @ViewBuilder
    private func chip(_ step: AfterCaptureStep) -> some View {
        if step.group == .share {
            ShareChip(image: step == .airdrop ? airdropIcon : step.appBundleIdentifier.flatMap(icon(forAppWithName:)), title: step.title, isOn: binding(for: step))
        } else {
            ToggleChip(symbol: step.symbol, title: step.title, isOn: binding(for: step))
                .disabled(step.dependsOn.map { !$0.isEnabled } ?? false)
        }
    }

    private func binding(for step: AfterCaptureStep) -> Binding<Bool> {
        _ = (openEditorAfterCapture, saveToDisk, copyToClipboard, openInFinder, builtInShare, uploadMedia)
        return Binding(get: { step.isEnabled }, set: { step.isEnabled = $0 })
    }
}
