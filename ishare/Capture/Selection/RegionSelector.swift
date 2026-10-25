import AppKit
import Defaults
import ishareCore

@MainActor
final class RegionSelector {
    enum Outcome: @unchecked Sendable {
        case region(NSScreen, CGRect)
        case fullScreen(NSScreen)
        case switchToWindow
        case cancelled
    }

    struct Area: @unchecked Sendable {
        let screen: NSScreen
        let rect: CGRect
    }

    enum Selection: @unchecked Sendable {
        case single(Outcome)
        case regions([Area])

        var outcome: Outcome {
            switch self {
            case let .single(outcome): outcome
            case let .regions(areas): areas.first.map { .region($0.screen, $0.rect) } ?? .cancelled
            }
        }
    }

    struct Options {
        var backdrops: [CGDirectDisplayID: CGImage] = [:]
        var allowsWindowMode = true
        var hint: String?
        var lastRegions: [CGDirectDisplayID: CGRect] = [:]
        var awaitsBackdrops = false
        var allowsMultipleRegions = false
        var allowsFreezeToggle = false
        var freezeMode = SelectionFreezeMode.frozen
        var liveSampler: LiveMagnifierSampler?
        var onFreezeModeChange: (@MainActor (SelectionFreezeMode) -> Void)?
    }

    private static var active: RegionSelector?
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<Selection, Never>?
    private var session: SelectionSession?

    static func select(options: Options = Options()) async -> Outcome {
        await selectRegions(options: options).outcome
    }

    static func selectRegions(options: Options = Options()) async -> Selection {
        active?.finish(.single(.cancelled))
        let selector = RegionSelector()
        active = selector
        let selection = await selector.run(options: options)
        active = nil
        return selection
    }

    private func run(options: Options) async -> Selection {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let session = SelectionSession(options: options)
            self.session = session
            session.onChange = { [weak self] in self?.redrawAll() }
            session.onFreezeModeChange = { [weak self] mode in self?.apply(freezeMode: mode) }
            options.liveSampler?.onSample = { [weak self] sample in
                self?.views.first { $0.displayID == sample.displayID }?.liveSample = sample
            }
            for screen in NSScreen.screens {
                let panel = SelectionPanel(screen: screen)
                let view = RegionSelectionView(
                    screen: screen,
                    backdrop: screen.displayID.flatMap { options.backdrops[$0] },
                    session: session
                ) { [weak self] selection in
                    self?.finish(selection)
                }
                panel.contentView = view
                panel.orderFrontRegardless()
                panels.append(panel)
            }
            let keyPanel = panels.first { $0.screen == NSScreen.underMouse } ?? panels.first
            keyPanel?.makeKey()
            if let view = keyPanel?.contentView {
                keyPanel?.makeFirstResponder(view)
            }
        }
    }

    static var panelWindowIDs: Set<CGWindowID> {
        Set(active?.panels.map { CGWindowID($0.windowNumber) } ?? [])
    }

    static var freezeMode: SelectionFreezeMode? {
        active?.session?.freezeMode
    }

    static func provide(backdrops: [CGDirectDisplayID: CGImage]) {
        active?.provide(backdrops: backdrops)
    }

    private var views: [RegionSelectionView] {
        panels.compactMap { $0.contentView as? RegionSelectionView }
    }

    private func provide(backdrops: [CGDirectDisplayID: CGImage]) {
        guard session?.freezeMode != .live else { return }
        for view in views {
            if let displayID = view.displayID, let backdrop = backdrops[displayID] {
                view.backdrop = backdrop
            }
            view.awaitsBackdrop = false
        }
    }

    private func apply(freezeMode: SelectionFreezeMode) {
        for view in views {
            switch freezeMode {
            case .live:
                view.backdrop = nil
                view.awaitsBackdrop = false
            case .frozen:
                view.awaitsBackdrop = true
            }
        }
    }

    private func redrawAll() {
        views.forEach { $0.needsDisplay = true }
    }

    private func finish(_ selection: Selection) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        session?.options.liveSampler?.stop()
        session = nil
        NSCursor.arrow.set()
        continuation.resume(returning: selection)
    }
}

@MainActor
final class SelectionSession {
    let options: RegionSelector.Options
    var onChange: (() -> Void)?
    var onFreezeModeChange: ((SelectionFreezeMode) -> Void)?

    private(set) var constraint: SelectionConstraint
    private(set) var freezeMode: SelectionFreezeMode
    private(set) var regions = SelectionRegionList()
    private(set) var sizeEntry: SizeEntryBuffer?
    var keepsRegions = false {
        didSet { onChange?() }
    }
    var hoveredRegionID: Int? {
        didSet {
            if oldValue != hoveredRegionID { onChange?() }
        }
    }

    init(options: RegionSelector.Options) {
        self.options = options
        constraint = Defaults[.selectionConstraint]
        freezeMode = options.freezeMode
    }

    var customSize: FixedSelectionSize? {
        Defaults[.customSelectionSize]
    }

    var isEnteringSize: Bool {
        sizeEntry != nil
    }

    func setConstraint(_ constraint: SelectionConstraint) {
        self.constraint = constraint
        Defaults[.selectionConstraint] = constraint
        onChange?()
    }

    func cycleAspect() {
        setConstraint(constraint.nextAspect())
    }

    func cycleFixedSize() {
        setConstraint(constraint.nextFixedSize(custom: customSize))
    }

    func beginSizeEntry() {
        sizeEntry = SizeEntryBuffer()
        onChange?()
    }

    func cancelSizeEntry() {
        sizeEntry = nil
        onChange?()
    }

    func typeIntoSizeEntry(_ characters: String) -> Bool {
        guard var entry = sizeEntry, entry.append(characters) else { return false }
        sizeEntry = entry
        onChange?()
        return true
    }

    func deleteBackwardInSizeEntry() {
        sizeEntry?.deleteBackward()
        onChange?()
    }

    func commitSizeEntry() -> Bool {
        guard let size = sizeEntry?.size() else { return false }
        sizeEntry = nil
        Defaults[.customSelectionSize] = size
        setConstraint(.fixed(size))
        return true
    }

    func toggleFreezeMode() {
        guard options.allowsFreezeToggle else { return }
        freezeMode = freezeMode.toggled
        onFreezeModeChange?(freezeMode)
        options.onFreezeModeChange?(freezeMode)
        onChange?()
    }

    @discardableResult
    func addRegion(_ rect: CGRect, displayID: CGDirectDisplayID) -> SelectionRegion? {
        let region = regions.add(rect, displayID: displayID)
        onChange?()
        return region
    }

    func removeRegion(id: Int) {
        regions.remove(id: id)
        if hoveredRegionID == id {
            hoveredRegionID = nil
        }
        onChange?()
    }

    func moveRegion(id: Int, by delta: CGVector, within bounds: CGRect) {
        regions.move(id: id, by: delta, within: bounds)
        onChange?()
    }

    func keepsSelection(shiftHeld: Bool) -> Bool {
        MultiRegionPolicy.keepsSelection(
            shiftHeld: shiftHeld, toggleEnabled: keepsRegions, hasKeptRegions: !regions.isEmpty, allowsMultiple: options.allowsMultipleRegions)
    }

    func areas(including pending: SelectionRegion?) -> [RegionSelector.Area] {
        MultiRegionPolicy.finalRegions(kept: regions.regions, pending: pending).compactMap { region in
            guard let screen = NSScreen.screen(for: region.displayID) else { return nil }
            return RegionSelector.Area(screen: screen, rect: ScreenGeometry.flippedVertically(region.rect, containerHeight: screen.frame.height))
        }
    }
}
