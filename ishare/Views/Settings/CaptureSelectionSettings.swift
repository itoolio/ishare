import Defaults
import ishareCore
import SwiftUI

struct CaptureSelectionSettings: View {
    @Default(.selectionConstraint) var constraint
    @Default(.customSelectionSize) var customSize
    @Default(.freezeScreenWhileSelecting) var freezeScreen
    @Default(.multiRegionResult) var multiRegionResult
    @Default(.menuCaptureIncludesParentWindow) var includesParentWindow

    var body: some View {
        Section {
            Picker("Selection shape".localized(), selection: $constraint) {
                ForEach(Self.choices(custom: customSize), id: \.self) { choice in
                    Text(Self.title(for: choice)).tag(choice)
                }
            }
            LabeledContent("Custom size".localized()) {
                HStack(spacing: 6) {
                    TextField("Width".localized(), value: customDimension(\.width), format: .number)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Text("×")
                    TextField("Height".localized(), value: customDimension(\.height), format: .number)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Picker("Unit".localized(), selection: customUnit) {
                        Text("Pixels".localized()).tag(SelectionSizeUnit.pixels)
                        Text("Points".localized()).tag(SelectionSizeUnit.points)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Use".localized()) {
                        constraint = .fixed(currentCustomSize)
                    }
                    .disabled(constraint == .fixed(currentCustomSize))
                }
            }
            Toggle("Freeze the screen while selecting".localized(), isOn: $freezeScreen)
            Picker("Multiple regions".localized(), selection: $multiRegionResult) {
                Text("Combine into one image".localized()).tag(MultiRegionResult.combined)
                Text("Save as separate captures".localized()).tag(MultiRegionResult.separate)
            }
            Toggle("Include the parent window when capturing menus".localized(), isOn: $includesParentWindow)
        } header: {
            Text("Selection".localized())
        } footer: {
            Text(
                "While selecting, press A to cycle aspect ratios, F to cycle fixed sizes and S to type a size such as 800x600. Hold ⌘ or press + to keep several regions, then press Return to capture them all. Tab switches between a frozen and a live screen. Capture Menu… counts down three seconds so you can open a menu, popover or tooltip first."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var currentCustomSize: FixedSelectionSize {
        customSize ?? FixedSelectionSize(width: 800, height: 600)
    }

    private func customDimension(_ keyPath: WritableKeyPath<FixedSelectionSize, Int>) -> Binding<Int> {
        Binding(
            get: { currentCustomSize[keyPath: keyPath] },
            set: { updateCustomSize(keyPath, to: $0) }
        )
    }

    private var customUnit: Binding<SelectionSizeUnit> {
        Binding(
            get: { currentCustomSize.unit },
            set: { updateCustomUnit($0) }
        )
    }

    private func updateCustomSize(_ keyPath: WritableKeyPath<FixedSelectionSize, Int>, to value: Int) {
        var size = currentCustomSize
        size[keyPath: keyPath] = value
        applyCustomSize(FixedSelectionSize(width: size.width, height: size.height, unit: size.unit))
    }

    private func updateCustomUnit(_ unit: SelectionSizeUnit) {
        let size = currentCustomSize
        applyCustomSize(FixedSelectionSize(width: size.width, height: size.height, unit: unit))
    }

    private func applyCustomSize(_ size: FixedSelectionSize) {
        let wasActive = customSize.map { constraint == .fixed($0) } ?? false
        customSize = size
        if wasActive {
            constraint = .fixed(size)
        }
    }

    static func choices(custom: FixedSelectionSize?) -> [SelectionConstraint] {
        var choices: [SelectionConstraint] = [.free]
        choices += AspectRatio.presets.map { .aspect($0) }
        choices += FixedSelectionSize.presets.map { .fixed($0) }
        if let custom, !FixedSelectionSize.presets.contains(custom) {
            choices.append(.fixed(custom))
        }
        return choices
    }

    static func title(for constraint: SelectionConstraint) -> String {
        switch constraint {
        case .free:
            "Free".localized()
        case let .aspect(ratio):
            String(format: "Aspect ratio %@".localized(), ratio.label)
        case let .fixed(size) where size == .socialCard:
            String(format: "%@ (social card)".localized(), size.label)
        case let .fixed(size):
            String(format: "Fixed size %@".localized(), size.label)
        }
    }
}
