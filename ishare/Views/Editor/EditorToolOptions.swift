import SwiftUI

struct EditorToolOptions: View {
    @ObservedObject var document: EditorDocument

    @State private var showingStampPicker = false

    static func hasOptions(for tool: EditorTool) -> Bool {
        switch tool {
        case .crop, .arrow, .line, .rectangle, .ellipse, .spotlight, .stamp: true
        default: false
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            switch document.tool {
            case .crop: cropOptions
            case .arrow: arrowOptions
            case .line, .rectangle, .ellipse: dashToggle
            case .spotlight: spotlightOptions
            case .stamp: stampOptions
            default: EmptyView()
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .adaptiveGlass(cornerRadius: 12)
    }

    private var cropOptions: some View {
        Group {
            Picker("Aspect Ratio".localized(), selection: Binding(
                get: { document.cropAspect },
                set: { document.setCropAspect($0) }
            )) {
                ForEach(CropAspect.allCases) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Aspect Ratio".localized())
            .accessibilityIdentifier("editor.crop.aspect")
            Button("Cancel".localized()) { document.cancelCropping() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("editor.crop.cancel")
            Button("Apply".localized()) { document.applyPendingCrop() }
                .keyboardShortcut(.return, modifiers: [])
                .adaptiveGlassButtonStyle(prominent: true)
                .accessibilityIdentifier("editor.crop.apply")
        }
    }

    private var arrowOptions: some View {
        Group {
            Picker("Arrow Style".localized(), selection: Binding(
                get: { document.arrowPath },
                set: { path in
                    document.arrowPath = path
                    document.updateSelection { $0.setArrowPath(path) }
                }
            )) {
                ForEach(ArrowPath.allCases) { path in
                    Image(systemName: path.symbol)
                        .help(path.title)
                        .accessibilityLabel(path.title)
                        .tag(path)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("editor.arrow.path")
            Toggle(isOn: Binding(
                get: { document.doubleHeaded },
                set: { value in
                    document.doubleHeaded = value
                    document.updateSelection { if $0.isArrow { $0.doubleHeaded = value } }
                }
            )) {
                Image(systemName: "arrow.left.and.right")
            }
            .toggleStyle(.button)
            .help("Double-Headed".localized())
            .accessibilityIdentifier("editor.arrow.double")
            Menu {
                Picker("Arrowhead".localized(), selection: Binding(
                    get: { document.arrowHead },
                    set: { head in
                        document.arrowHead = head
                        document.updateSelection { if $0.isArrow { $0.arrowHead = head } }
                    }
                )) {
                    ForEach(ArrowHead.allCases) { head in
                        Label(head.title, systemImage: head.symbol).tag(head)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: document.arrowHead.symbol)
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("Arrowhead".localized())
            .accessibilityIdentifier("editor.arrow.head")
            dashToggle
        }
    }

    private var dashToggle: some View {
        Toggle(isOn: Binding(
            get: { document.dashed },
            set: { value in
                document.dashed = value
                document.updateSelection { if $0.supportsDash { $0.dashed = value } }
            }
        )) {
            Image(systemName: "rectangle.dashed")
        }
        .toggleStyle(.button)
        .help("Dashed".localized())
        .accessibilityIdentifier("editor.style.dashed")
    }

    private var spotlightOptions: some View {
        Group {
            Picker("Spotlight Shape".localized(), selection: Binding(
                get: { document.spotlightShape },
                set: { shape in
                    document.spotlightShape = shape
                    document.updateSelection { if $0.isSpotlight { $0.spotlightShape = shape } }
                }
            )) {
                ForEach(SpotlightShape.allCases) { shape in
                    Image(systemName: shape.symbol)
                        .help(shape.title)
                        .accessibilityLabel(shape.title)
                        .tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("editor.spotlight.shape")
            Label("Dim".localized(), systemImage: "circle.lefthalf.filled")
                .labelStyle(.iconOnly)
                .help("Dim".localized())
            Slider(value: Binding(
                get: { document.dimAmount },
                set: { document.setDimAmount($0) }
            ), in: 0.1 ... 0.95) { editing in
                if editing {
                    document.beginContinuousChange()
                } else {
                    document.endContinuousChange()
                }
            }
            .frame(width: 110)
            .help("Dim".localized())
            .accessibilityIdentifier("editor.spotlight.dim")
        }
    }

    private var stampOptions: some View {
        Button {
            showingStampPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                StampPreview(stamp: document.stamp, color: document.color, size: 18)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .help("Choose Stamp".localized())
        .accessibilityIdentifier("editor.stamp.picker")
        .popover(isPresented: $showingStampPicker, arrowEdge: .bottom) {
            StampPicker(document: document) { stamp in
                document.stamp = stamp
                document.updateSelection { annotation in
                    if case let .stamp(rect, _) = annotation.shape {
                        annotation.shape = .stamp(rect, stamp)
                    }
                }
                showingStampPicker = false
            }
        }
    }
}

extension Annotation {
    mutating func setArrowPath(_ path: ArrowPath) {
        switch (shape, path) {
        case let (.arrow(start, end), .curved):
            shape = .curvedArrow(start, ArrowGeometry.defaultControl(from: start, to: end), end)
        case let (.curvedArrow(start, _, end), .straight):
            shape = .arrow(start, end)
        default:
            break
        }
    }
}
