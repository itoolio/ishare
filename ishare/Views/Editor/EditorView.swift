import Defaults
import SwiftUI

struct EditorView: View {
    @ObservedObject var document: EditorDocument
    var onDone: () -> Void
    var onDiscard: () -> Void
    var onCopy: () -> Void

    @StateObject private var viewport: EditorViewport
    @ObservedObject private var templates = TemplateStore.shared
    @Default(.editorShowsLayers) private var showsLayers
    @State private var showsAdjustments = false
    @State private var showsBeautify = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(document: EditorDocument, onDone: @escaping () -> Void, onDiscard: @escaping () -> Void, onCopy: @escaping () -> Void) {
        self.document = document
        self.onDone = onDone
        self.onDiscard = onDiscard
        self.onCopy = onCopy
        _viewport = StateObject(wrappedValue: EditorViewport(visibleRect: document.visibleRect))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            HStack(spacing: 0) {
                EditorCanvas(document: document, viewport: viewport)
                    .background(Color.black.opacity(0.18))
                    .overlay {
                        if document.isProcessing {
                            ProgressView()
                                .controlSize(.large)
                                .padding(18)
                                .adaptiveGlass(cornerRadius: 14)
                                .accessibilityIdentifier("editor.processing")
                        }
                    }
                if showsLayers {
                    Divider()
                    LayersSidebar(document: document)
                        .transition(MotionPreference.transition(.move(edge: .trailing), reducesMotion: reduceMotion))
                }
            }
            bottomBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 980, minHeight: 560)
        .background(.background)
        .sheet(isPresented: $showsBeautify) {
            EditorBeautifySheet(document: document) { showsBeautify = false }
        }
        .onChange(of: showsAdjustments) { _, shown in
            if !shown {
                document.straightenAngle = 0
            }
        }
        .onDeleteCommand {
            if document.editingText == nil {
                document.deleteSelection()
            }
        }
        .onExitCommand {
            if document.editingText != nil {
                document.commitText()
            } else if document.isCropping {
                document.cancelCropping()
            } else {
                document.selectedID = nil
            }
        }
    }

    private var toolbar: some View {
        AdaptiveGlassContainer(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    toolButtons
                    panelButtons
                    if EditorToolOptions.hasOptions(for: document.tool) {
                        EditorToolOptions(document: document)
                    }
                }
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        toolButtons
                        panelButtons
                    }
                    if EditorToolOptions.hasOptions(for: document.tool) {
                        EditorToolOptions(document: document)
                    }
                }
                VStack(spacing: 6) {
                    toolButtons
                    HStack(spacing: 8) {
                        panelButtons
                        if EditorToolOptions.hasOptions(for: document.tool) {
                            EditorToolOptions(document: document)
                        }
                    }
                }
            }
        }
    }

    private var toolButtons: some View {
        HStack(spacing: 4) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    document.select(tool: tool)
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 28)
                        .foregroundStyle(document.tool == tool ? Color.white : Color.primary)
                        .background {
                            if document.tool == tool {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
                            }
                        }
                        .overlay {
                            if contrast.isHigh, document.tool != tool {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: contrast.borderWidth)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(tool.title.localized()) (\(String(tool.shortcut).uppercased()))")
                .keyboardShortcut(document.editingText == nil ? KeyboardShortcut(KeyEquivalent(tool.shortcut), modifiers: []) : nil)
                .accessibilityLabel(tool.accessibilityLabel)
                .accessibilityAddTraits(document.tool == tool ? .isSelected : [])
                .accessibilityIdentifier("editor.tool.\(tool.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .padding(5)
        .adaptiveGlass(cornerRadius: 12)
        .fixedSize()
    }

    private var panelButtons: some View {
        HStack(spacing: 4) {
            TemplatesButton(document: document, store: templates)
            Button {
                withMotionAnimation(.easeInOut(duration: 0.18)) { showsLayers.toggle() }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 28)
                    .foregroundStyle(showsLayers ? Color.white : Color.primary)
                    .background {
                        if showsLayers {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("l", modifiers: .command)
            .help("Layers".localized() + " (⌘L)")
            .accessibilityLabel("Layers".localized())
            .accessibilityToggleState(showsLayers)
            .accessibilityIdentifier("editor.layers.toggle")
        }
        .padding(5)
        .adaptiveGlass(cornerRadius: 12)
        .fixedSize()
    }

    private var contrast: MenuContrast {
        MenuContrast.resolve(colorSchemeContrast)
    }

    private var showsWidthSlider: Bool {
        switch document.tool {
        case .stamp, .spotlight, .crop, .blur, .pixelate, .eraser: false
        default: true
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                styleControls(compactColors: false)
                styleControls(compactColors: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                ZoomControls(viewport: viewport, selectionBounds: document.selectionBounds, showsSlider: true)
                ZoomControls(viewport: viewport, selectionBounds: document.selectionBounds, showsSlider: false)
            }
            .fixedSize(horizontal: false, vertical: true)
            actionButtons
                .fixedSize()
                .layoutPriority(1)
        }
        .controlSize(.regular)
    }

    private func styleControls(compactColors: Bool) -> some View {
        HStack(spacing: 12) {
            colorControls(compact: compactColors)
            Divider().frame(height: 20)
            if document.tool.supportsFill {
                Toggle(isOn: $document.filled) {
                    Image(systemName: "paintbrush.pointed.fill")
                }
                .toggleStyle(.button)
                .help("Fill".localized())
            }
            if document.tool == .text {
                Toggle(isOn: $document.textBackground) {
                    Image(systemName: "character.textbox")
                }
                .toggleStyle(.button)
                .help("Text background".localized())
            }
            if document.tool.usesFont || document.tool == .cursor {
                Label("Size".localized(), systemImage: "textformat.size")
                    .labelStyle(.iconOnly)
                Slider(value: $document.fontSize, in: 12 ... 160)
                    .frame(width: compactColors ? 80 : 110)
            } else if showsWidthSlider {
                Label("Width".localized(), systemImage: "lineweight")
                    .labelStyle(.iconOnly)
                Slider(value: $document.lineWidth, in: 1 ... 40)
                    .frame(width: compactColors ? 80 : 110)
            }
            Divider().frame(height: 20)
            historyControls
        }
        .fixedSize()
    }

    @ViewBuilder
    private func colorControls(compact: Bool) -> some View {
        if compact {
            Menu {
                ForEach(RGBAColor.palette, id: \.self) { swatch in
                    Button {
                        applyColor(swatch)
                    } label: {
                        Image(nsImage: swatchImage(swatch))
                    }
                }
            } label: {
                Image(nsImage: swatchImage(document.color))
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("Color".localized())
            .accessibilityIdentifier("editor.color")
        } else {
            HStack(spacing: 6) {
                ForEach(RGBAColor.palette, id: \.self) { swatch in
                    Button {
                        applyColor(swatch)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: swatch.nsColor))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(document.color == swatch ? 0.9 : 0.15), lineWidth: document.color == swatch ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        ColorPicker(
            "",
            selection: Binding(
                get: { Color(nsColor: document.color.nsColor) },
                set: { document.color = RGBAColor(NSColor($0)) }
            )
        )
        .labelsHidden()
        .frame(width: 28)
    }

    private func swatchImage(_ color: RGBAColor) -> NSImage {
        NSImage(size: CGSize(width: 14, height: 14), flipped: false) { rect in
            color.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
            return true
        }
    }

    private var historyControls: some View {
        HStack(spacing: 8) {
            Button {
                document.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!document.canUndo)
            .help("Undo".localized())
            Button {
                document.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!document.canRedo)
            .help("Redo".localized())
            Menu {
                Button("Rotate Left".localized()) { document.apply(.rotateLeft) }
                Button("Rotate Right".localized()) { document.apply(.rotateRight) }
                Divider()
                Button("Flip Horizontally".localized()) { document.apply(.flipHorizontal) }
                Button("Flip Vertically".localized()) { document.apply(.flipVertical) }
                Divider()
                Button("Straighten…".localized()) { showsAdjustments = true }
                if document.crop != nil {
                    Divider()
                    Button("Reset Crop".localized()) { document.resetCrop() }
                }
            } label: {
                Image(systemName: "rotate.right")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Transform".localized())
            .accessibilityIdentifier("editor.transform")
            Button {
                showsAdjustments.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Adjust".localized())
            .accessibilityLabel("Adjust".localized())
            .accessibilityIdentifier("editor.adjust")
            .popover(isPresented: $showsAdjustments, arrowEdge: .top) {
                EditorAdjustPanel(document: document)
            }
            imageActionsMenu
        }
    }

    private var imageActionsMenu: some View {
        Menu {
            Button("Beautify…".localized()) {
                document.commitPendingEdits()
                showsBeautify = true
            }
            Button("Lift Subject".localized()) {
                Task { await document.liftSubject() }
            }
            .disabled(document.isProcessing)
            Button("Combine with…".localized()) { combineWithFiles() }
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .helpAndAccessibilityLabel("Image Actions".localized())
        .accessibilityIdentifier("editor.imageActions")
    }

    private var exportMenu: some View {
        Menu {
            ForEach(EditorExportFormat.allCases) { format in
                Button(format.title) { EditorExport.export(document, as: format) }
            }
        } label: {
            Label("Export".localized(), systemImage: "square.and.arrow.up")
        }
        .fixedSize()
        .accessibilityIdentifier("editor.export")
    }

    private func combineWithFiles() {
        document.commitPendingEdits()
        let urls = NewCaptureDocument.chooseImages(message: "Choose images to combine with this capture".localized())
        guard !urls.isEmpty, let current = document.render() else { return }
        CombineWindowController.present(urls: urls, leading: [current])
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(role: .destructive, action: onDiscard) {
                Label("Discard".localized(), systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .accessibilityIdentifier("editor.discard")
            exportMenu
            Button(action: onCopy) {
                Label("Copy".localized(), systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            .accessibilityIdentifier("editor.copy")
            Button(action: {
                document.commitPendingEdits()
                onDone()
            }) {
                Label("Done".localized(), systemImage: "checkmark")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .adaptiveGlassButtonStyle(prominent: true)
            .accessibilityIdentifier("editor.done")
        }
    }

    private func applyColor(_ color: RGBAColor) {
        document.color = color
        document.updateSelection { $0.color = color }
    }
}

struct ZoomControls: View {
    @ObservedObject var viewport: EditorViewport
    var selectionBounds: CGRect?
    var showsSlider: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button {
                viewport.zoomOut(selection: selectionBounds)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom Out".localized())
            .accessibilityIdentifier("editor.zoom.out")
            if showsSlider {
                Slider(
                    value: Binding(
                        get: { log2(viewport.effectiveZoom) },
                        set: { viewport.setZoom(pow(2, $0)) }
                    ), in: log2(CanvasTransform.minimumZoom) ... log2(CanvasTransform.maximumZoom)
                )
                .frame(width: 90)
                .help("Zoom".localized())
                .accessibilityIdentifier("editor.zoom.slider")
            }
            Button {
                viewport.zoomIn(selection: selectionBounds)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)
            .help("Zoom In".localized())
            .accessibilityIdentifier("editor.zoom.in")
            Button("") { viewport.zoomIn(selection: selectionBounds) }
                .keyboardShortcut("=", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            Text(verbatim: "\(viewport.percentage)%")
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 44)
                .accessibilityIdentifier("editor.zoom.percentage")
            Button("Fit".localized()) { viewport.fit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(viewport.isFit)
                .accessibilityIdentifier("editor.zoom.fit")
            Button("100%".localized()) { viewport.actualSize() }
                .keyboardShortcut("1", modifiers: .command)
                .accessibilityIdentifier("editor.zoom.actual")
        }
        .fixedSize()
    }
}
