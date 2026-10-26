import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct SelectionConstraintTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func cyclesThroughTheAspectPresetsAndBackToFree() {
        var constraint = SelectionConstraint.free
        var seen: [String?] = []
        for _ in 0 ..< 6 {
            constraint = constraint.nextAspect()
            seen.append(constraint.label)
        }
        #expect(seen == ["16:9", "4:3", "3:2", "1:1", "9:16", nil])
        #expect(SelectionConstraint.fixed(.hd).nextAspect() == .aspect(.widescreen))
    }

    @Test func cyclesThroughFixedSizesIncludingTheCustomOne() {
        let custom = FixedSelectionSize(width: 800, height: 600, unit: .points)
        var constraint = SelectionConstraint.aspect(.square)
        var seen: [SelectionConstraint] = []
        for _ in 0 ..< 5 {
            constraint = constraint.nextFixedSize(custom: custom)
            seen.append(constraint)
        }
        #expect(seen == [.fixed(.hd), .fixed(.fullHD), .fixed(.socialCard), .fixed(custom), .free])
        #expect(SelectionConstraint.fixed(.socialCard).nextFixedSize(custom: nil) == .free)
        #expect(SelectionConstraint.fixed(.socialCard).nextFixedSize(custom: .hd) == .free)
    }

    @Test func constrainsDragsToTheRatioInEveryDirection() {
        let anchor = CGPoint(x: 500, y: 400)
        #expect(
            SelectionConstraintMath.aspectRect(from: anchor, to: CGPoint(x: 660, y: 410), ratio: .widescreen, within: bounds)
                == CGRect(x: 500, y: 400, width: 160, height: 90))
        #expect(
            SelectionConstraintMath.aspectRect(from: anchor, to: CGPoint(x: 490, y: 310), ratio: .widescreen, within: bounds)
                == CGRect(x: 340, y: 310, width: 160, height: 90))
        #expect(
            SelectionConstraintMath.aspectRect(from: anchor, to: CGPoint(x: 400, y: 600), ratio: .portrait, within: bounds)
                == CGRect(x: 387.5, y: 400, width: 112.5, height: 200))
    }

    @Test func keepsTheRatioWhenTheDragHitsTheScreenEdge() {
        let rect = SelectionConstraintMath.aspectRect(from: CGPoint(x: 900, y: 100), to: CGPoint(x: 1200, y: 120), ratio: .square, within: bounds)
        #expect(rect == CGRect(x: 900, y: 100, width: 100, height: 100))
        let tall = SelectionConstraintMath.aspectRect(from: CGPoint(x: 100, y: 700), to: CGPoint(x: 900, y: 750), ratio: .widescreen, within: bounds)
        #expect(tall.height == 100)
        #expect(abs(tall.width / tall.height - 16.0 / 9.0) < 0.0001)
    }

    @Test func centersFixedSizesOnThePointerAndKeepsThemOnScreen() {
        let size = FixedSelectionSize.hd.pointSize(scale: 2)
        #expect(size == CGSize(width: 640, height: 360))
        #expect(SelectionConstraintMath.fixedRect(size: size, centeredAt: CGPoint(x: 500, y: 400), within: bounds) == CGRect(x: 180, y: 220, width: 640, height: 360))
        #expect(SelectionConstraintMath.fixedRect(size: size, centeredAt: CGPoint(x: 990, y: 10), within: bounds) == CGRect(x: 360, y: 0, width: 640, height: 360))
        let oversized = SelectionConstraintMath.fixedRect(size: CGSize(width: 2000, height: 100), centeredAt: CGPoint(x: 10, y: 10), within: bounds)
        #expect(oversized == CGRect(x: 0, y: 0, width: 1000, height: 100))
    }

    @Test func alignsFixedRectsToThePixelGrid() {
        let size = FixedSelectionSize(width: 1201, height: 631).pointSize(scale: 2)
        let rect = SelectionConstraintMath.fixedRect(size: size, centeredAt: CGPoint(x: 500.3, y: 400.1), within: bounds, scale: 2)
        #expect(ScreenGeometry.pixelRect(for: rect, scale: 2).size == CGSize(width: 1201, height: 631))
        #expect((rect.minX * 2).truncatingRemainder(dividingBy: 1) == 0)
    }

    @Test func convertsBetweenPointsAndPixels() {
        let points = FixedSelectionSize(width: 800, height: 600, unit: .points)
        #expect(points.pixelSize(scale: 2) == CGSize(width: 1600, height: 1200))
        #expect(points.pointSize(scale: 2) == CGSize(width: 800, height: 600))
        #expect(FixedSelectionSize.fullHD.pixelSize(scale: 2) == CGSize(width: 1920, height: 1080))
        #expect(FixedSelectionSize.fullHD.detailedLabel(scale: 2) == "1920 × 1080 px · 960 × 540 pt")
        #expect(FixedSelectionSize.fullHD.detailedLabel(scale: 1) == "1920 × 1080 px")
        #expect(points.detailedLabel(scale: 1) == "800 × 600 px · 800 × 600 pt")
    }

    @Test func parsesTypedSizes() {
        #expect(FixedSelectionSize.parse("800x600") == FixedSelectionSize(width: 800, height: 600, unit: .pixels))
        #expect(FixedSelectionSize.parse(" 800 × 600 pt ") == FixedSelectionSize(width: 800, height: 600, unit: .points))
        #expect(FixedSelectionSize.parse("1024*768px", defaultUnit: .points) == FixedSelectionSize(width: 1024, height: 768, unit: .pixels))
        #expect(FixedSelectionSize.parse("800 600") == FixedSelectionSize(width: 800, height: 600))
        #expect(FixedSelectionSize.parse("800x") == nil)
        #expect(FixedSelectionSize.parse("0x600") == nil)
        #expect(FixedSelectionSize.parse("800x600x2") == nil)
        #expect(FixedSelectionSize.parse("99999x10") == nil)
    }

    @Test func sizeEntryBufferOnlyAcceptsSizeCharacters() {
        var buffer = SizeEntryBuffer()
        let acceptsNumber = buffer.append("8")
        let acceptsSeparator = buffer.append("00X6")
        let rejectsLetter = buffer.append("q")
        #expect(acceptsNumber && acceptsSeparator && !rejectsLetter)
        buffer.append("00")
        #expect(buffer.text == "800x600")
        buffer.deleteBackward()
        #expect(buffer.size() == FixedSelectionSize(width: 800, height: 60))
        let acceptsOverflow = buffer.append("12345678901234567")
        #expect(!acceptsOverflow)
        var empty = SizeEntryBuffer()
        empty.deleteBackward()
        #expect(empty.text.isEmpty)
        #expect(empty.size() == nil)
    }

    @Test func constraintsRoundTripThroughCodable() throws {
        let values: [SelectionConstraint] = [.free, .aspect(.portrait), .fixed(FixedSelectionSize(width: 10, height: 20, unit: .points))]
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode([SelectionConstraint].self, from: data) == values)
    }
}

struct SelectionRegionListTests {
    let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)

    @Test func numbersRegionsInTheOrderTheyWereAdded() {
        var list = SelectionRegionList()
        let first = list.add(CGRect(x: 0, y: 0, width: 50, height: 50), displayID: 1)
        let second = list.add(CGRect(x: 100, y: 100, width: 50, height: 50), displayID: 2)
        let third = list.add(CGRect(x: 200, y: 200, width: 50, height: 50), displayID: 1)
        #expect(list.regions.map(\.id) == [first?.id, second?.id, third?.id].compactMap { $0 })
        #expect(list.number(of: third!.id) == 3)
        #expect(list.displayIDs == [1, 2])
        #expect(list.regions(onDisplay: 1).map(\.id) == [first!.id, third!.id])
    }

    @Test func ignoresTinySelections() {
        var list = SelectionRegionList()
        let tiny = list.add(CGRect(x: 0, y: 0, width: 2, height: 50), displayID: 1)
        #expect(tiny == nil)
        #expect(list.isEmpty)
    }

    @Test func renumbersAfterRemovalWithoutReusingIDs() {
        var list = SelectionRegionList()
        let first = list.add(CGRect(x: 0, y: 0, width: 50, height: 50), displayID: 1)!
        let second = list.add(CGRect(x: 60, y: 0, width: 50, height: 50), displayID: 1)!
        let removed = list.remove(id: first.id)
        #expect(removed == first)
        #expect(list.number(of: second.id) == 1)
        let third = list.add(CGRect(x: 120, y: 0, width: 50, height: 50), displayID: 1)!
        #expect(third.id != first.id)
        #expect(list.number(of: third.id) == 2)
        let missing = list.remove(id: 999)
        #expect(missing == nil)
    }

    @Test func hitTestsTheMostRecentRegionOnTheSameDisplay() {
        var list = SelectionRegionList()
        let below = list.add(CGRect(x: 0, y: 0, width: 100, height: 100), displayID: 1)!
        let above = list.add(CGRect(x: 50, y: 50, width: 100, height: 100), displayID: 1)!
        #expect(list.region(at: CGPoint(x: 75, y: 75), displayID: 1) == above)
        #expect(list.region(at: CGPoint(x: 10, y: 10), displayID: 1) == below)
        #expect(list.region(at: CGPoint(x: 75, y: 75), displayID: 2) == nil)
    }

    @Test func movesRegionsWithinTheirDisplay() {
        var list = SelectionRegionList()
        let region = list.add(CGRect(x: 400, y: 10, width: 80, height: 80), displayID: 1)!
        let moved = list.move(id: region.id, by: CGVector(dx: 100, dy: -50), within: bounds)
        #expect(moved?.rect == CGRect(x: 420, y: 0, width: 80, height: 80))
        #expect(list.number(of: region.id) == 1)
    }

    @Test func limitsTheNumberOfRegions() {
        var list = SelectionRegionList()
        for index in 0 ..< SelectionRegionList.maximumCount {
            list.add(CGRect(x: index, y: 0, width: 10, height: 10), displayID: 1)
        }
        let overflow = list.add(CGRect(x: 0, y: 0, width: 10, height: 10), displayID: 1)
        #expect(overflow == nil)
        list.removeAll()
        #expect(list.isEmpty)
    }

    @Test func decidesWhenSelectionsAreKept() {
        #expect(MultiRegionPolicy.keepsSelection(keepModifierHeld: true, toggleEnabled: false, hasKeptRegions: false, allowsMultiple: true))
        #expect(MultiRegionPolicy.keepsSelection(keepModifierHeld: false, toggleEnabled: true, hasKeptRegions: false, allowsMultiple: true))
        #expect(MultiRegionPolicy.keepsSelection(keepModifierHeld: false, toggleEnabled: false, hasKeptRegions: true, allowsMultiple: true))
        #expect(!MultiRegionPolicy.keepsSelection(keepModifierHeld: false, toggleEnabled: false, hasKeptRegions: false, allowsMultiple: true))
        #expect(!MultiRegionPolicy.keepsSelection(keepModifierHeld: true, toggleEnabled: true, hasKeptRegions: true, allowsMultiple: false))
    }

    @Test func appendsThePendingSelectionWhenFinishing() {
        let kept = [SelectionRegion(id: 1, displayID: 1, rect: CGRect(x: 0, y: 0, width: 10, height: 10))]
        let pending = SelectionRegion(id: 0, displayID: 2, rect: CGRect(x: 0, y: 0, width: 20, height: 20))
        #expect(MultiRegionPolicy.finalRegions(kept: kept, pending: pending).map(\.displayID) == [1, 2])
        #expect(MultiRegionPolicy.finalRegions(kept: kept, pending: SelectionRegion(id: 0, displayID: 2, rect: .zero)) == kept)
        #expect(MultiRegionPolicy.finalRegions(kept: kept, pending: nil) == kept)
    }
}

struct SelectionFreezeModeTests {
    @Test func followsThePreferenceAndToggles() {
        #expect(SelectionFreezeMode(prefersFrozen: true) == .frozen)
        #expect(SelectionFreezeMode(prefersFrozen: false) == .live)
        #expect(SelectionFreezeMode.frozen.toggled == .live)
        #expect(SelectionFreezeMode.live.toggled.toggled == .live)
        #expect(SelectionFreezeMode.frozen.loadsBackdrops)
        #expect(!SelectionFreezeMode.live.loadsBackdrops)
    }

    @Test func picksWhereTheImageComesFrom() {
        #expect(SelectionFreezePolicy.imageSource(mode: .frozen, hasBackdrop: true, delay: 0) == .backdrop)
        #expect(SelectionFreezePolicy.imageSource(mode: .frozen, hasBackdrop: false, delay: 0) == .liveCapture(settle: .zero))
        #expect(SelectionFreezePolicy.imageSource(mode: .live, hasBackdrop: true, delay: 0) == .liveCapture(settle: SelectionFreezePolicy.liveSettleDelay))
        #expect(SelectionFreezePolicy.imageSource(mode: .frozen, hasBackdrop: true, delay: 3) == .afterCountdown)
        #expect(SelectionFreezePolicy.imageSource(mode: .live, hasBackdrop: false, delay: 5) == .afterCountdown)
    }

    @Test func picksTheMagnifierSource() {
        func source(_ mode: SelectionFreezeMode, enabled: Bool = true, backdrop: Bool = false, awaiting: Bool = false, sampling: Bool = false) -> SelectionMagnifierSource {
            SelectionFreezePolicy.magnifierSource(enabled: enabled, mode: mode, hasBackdrop: backdrop, awaitingBackdrop: awaiting, liveSamplingAvailable: sampling)
        }
        #expect(source(.frozen, enabled: false, backdrop: true) == .hidden)
        #expect(source(.frozen, backdrop: true) == .backdrop)
        #expect(source(.frozen, awaiting: true) == .pending)
        #expect(source(.frozen) == .position)
        #expect(source(.live, backdrop: true, sampling: true) == .liveSample)
        #expect(source(.live, backdrop: true) == .position)
    }

    @Test func throttlesLiveSamples() throws {
        var throttle = SamplingThrottle(minimumInterval: 0.1, slowLatency: 0.2, slowSampleLimit: 2)
        #expect(throttle.delayBeforeNextRequest(at: 0) == 0)
        throttle.begin(at: 0)
        #expect(throttle.delayBeforeNextRequest(at: 0.01) == nil)
        throttle.finish(at: 0.03)
        let wait = try #require(throttle.delayBeforeNextRequest(at: 0.04))
        #expect(abs(wait - 0.06) < 0.0001)
        #expect(throttle.delayBeforeNextRequest(at: 0.5) == 0)
    }

    @Test func disablesSamplingWhenItIsTooSlow() {
        var throttle = SamplingThrottle(minimumInterval: 0.05, slowLatency: 0.2, slowSampleLimit: 2)
        throttle.begin(at: 0)
        throttle.finish(at: 0.3)
        throttle.begin(at: 1)
        throttle.finish(at: 1.05)
        throttle.begin(at: 2)
        throttle.finish(at: 2.3)
        #expect(!throttle.isDisabled)
        throttle.begin(at: 3)
        throttle.finish(at: 3.3)
        #expect(throttle.isDisabled)
        #expect(throttle.delayBeforeNextRequest(at: 10) == nil)
    }

    @Test func disablesSamplingAfterRepeatedFailures() {
        var throttle = SamplingThrottle(slowSampleLimit: 2)
        throttle.begin(at: 0)
        throttle.fail()
        #expect(!throttle.isDisabled)
        throttle.begin(at: 1)
        throttle.fail()
        #expect(throttle.isDisabled)
    }
}

struct WindowClassificationTests {
    let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    var classifier: WindowClassifier {
        WindowClassifier(
            ownBundleID: "dev.adrian.ishare", ignoredBundleIDs: ["com.example.ignored"], displayFrames: [display],
            menuBarStrips: [WindowClassifier.menuBarStrip(forDisplay: display, height: 37)]
        )
    }

    func window(_ id: UInt32, layer: Int = 0, frame: CGRect, pid: Int32? = 10, bundle: String? = "com.example.app", onScreen: Bool = true) -> WindowDescriptor {
        WindowDescriptor(id: id, layer: layer, frame: frame, isOnScreen: onScreen, ownerPID: pid, ownerBundleID: bundle)
    }

    @Test func classifiesStandardWindowsAndPopups() {
        #expect(classifier.kind(of: window(1, frame: CGRect(x: 100, y: 100, width: 800, height: 600))) == .standard)
        #expect(classifier.kind(of: window(2, layer: 101, frame: CGRect(x: 120, y: 37, width: 240, height: 300))) == .popup)
        #expect(classifier.kind(of: window(3, layer: 200, frame: CGRect(x: 300, y: 300, width: 80, height: 22))) == .popup)
        #expect(classifier.kind(of: window(4, layer: 8, frame: CGRect(x: 300, y: 300, width: 400, height: 200))) == .popup)
    }

    @Test func excludesSystemChromeAndTinyOrHiddenWindows() {
        #expect(classifier.kind(of: window(1, frame: CGRect(x: 0, y: 0, width: 30, height: 600))) == nil)
        #expect(classifier.kind(of: window(2, layer: 101, frame: CGRect(x: 0, y: 0, width: 6, height: 40))) == nil)
        #expect(classifier.kind(of: window(3, frame: CGRect(x: 0, y: 0, width: 400, height: 400), onScreen: false)) == nil)
        #expect(classifier.kind(of: window(4, layer: 24, frame: CGRect(x: 0, y: 0, width: 1512, height: 37))) == nil)
        #expect(classifier.kind(of: window(5, layer: 25, frame: CGRect(x: 1200, y: 0, width: 30, height: 37), bundle: "com.apple.controlcenter")) == nil)
        #expect(classifier.kind(of: window(6, layer: 20, frame: CGRect(x: 0, y: 900, width: 1512, height: 82), bundle: "com.apple.dock")) == nil)
        #expect(classifier.kind(of: window(7, layer: 101, frame: CGRect(x: 0, y: 900, width: 200, height: 82), bundle: "com.apple.dock")) == nil)
        #expect(classifier.kind(of: window(8, layer: -2_147_483_624, frame: display, bundle: "com.apple.wallpaper.agent")) == nil)
        #expect(classifier.kind(of: window(9, layer: 101, frame: CGRect(x: 1100, y: 37, width: 380, height: 600), bundle: "com.apple.notificationcenterui")) == nil)
        #expect(classifier.kind(of: window(10, layer: 101, frame: CGRect(x: 100, y: 100, width: 200, height: 200), bundle: "dev.adrian.ishare")) == nil)
        #expect(classifier.kind(of: window(11, frame: CGRect(x: 100, y: 100, width: 200, height: 200), bundle: "com.example.ignored")) == nil)
        #expect(classifier.kind(of: window(12, layer: 1000, frame: CGRect(x: 100, y: 100, width: 200, height: 200))) == nil)
        #expect(classifier.kind(of: window(13, frame: CGRect(x: 100, y: 100, width: 200, height: 200), pid: nil, bundle: nil)) == nil)
    }

    @Test func ignoresPopupLevelOverlaysCoveringTheWholeDisplay() {
        #expect(classifier.kind(of: window(1, layer: 102, frame: display)) == nil)
        #expect(classifier.kind(of: window(2, frame: display)) == .standard)
    }

    @Test func keepsStatusMenusThatHangBelowTheMenuBar() {
        #expect(classifier.kind(of: window(1, layer: 25, frame: CGRect(x: 1100, y: 37, width: 320, height: 400), bundle: "com.apple.controlcenter")) == .popup)
    }

    @Test func prefersPopupsWhenHitTesting() {
        let windows = classifier.classify([
            window(1, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
            window(2, layer: 101, frame: CGRect(x: 100, y: 100, width: 200, height: 300)),
        ])
        #expect(WindowClassifier.preferredIndex(at: CGPoint(x: 150, y: 150), in: windows) == 1)
        #expect(WindowClassifier.preferredIndex(at: CGPoint(x: 600, y: 500), in: windows) == 0)
        #expect(WindowClassifier.preferredIndex(at: CGPoint(x: 1400, y: 900), in: windows) == nil)
    }

    @Test func picksTheMenuToCaptureAfterTheCountdown() {
        let windows = classifier.classify([
            window(1, frame: CGRect(x: 0, y: 40, width: 800, height: 600)),
            window(2, layer: 3, frame: CGRect(x: 900, y: 100, width: 200, height: 200)),
            window(3, layer: 101, frame: CGRect(x: 100, y: 37, width: 200, height: 300)),
            window(4, layer: 101, frame: CGRect(x: 300, y: 120, width: 200, height: 200)),
        ])
        #expect(WindowClassifier.menuTarget(at: CGPoint(x: 350, y: 150), in: windows) == 3)
        #expect(WindowClassifier.menuTarget(at: CGPoint(x: 700, y: 500), in: windows) == 2)
        let floatingOnly = classifier.classify([window(5, layer: 3, frame: CGRect(x: 900, y: 100, width: 200, height: 200))])
        #expect(WindowClassifier.menuTarget(at: .zero, in: floatingOnly) == 0)
        #expect(WindowClassifier.menuTarget(at: .zero, in: classifier.classify([window(1, frame: CGRect(x: 0, y: 40, width: 800, height: 600))])) == nil)
    }

    @Test func groupsCascadingSubmenusOfTheSameApp() {
        let windows = classifier.classify([
            window(1, layer: 101, frame: CGRect(x: 300, y: 120, width: 200, height: 200)),
            window(2, layer: 101, frame: CGRect(x: 100, y: 37, width: 200, height: 300)),
            window(3, layer: 101, frame: CGRect(x: 502, y: 200, width: 150, height: 100)),
            window(4, layer: 101, frame: CGRect(x: 900, y: 600, width: 100, height: 100)),
            window(5, layer: 101, frame: CGRect(x: 640, y: 210, width: 100, height: 100), pid: 99, bundle: "com.example.other"),
            window(6, frame: CGRect(x: 0, y: 40, width: 800, height: 600)),
        ])
        #expect(WindowClassifier.relatedPopups(of: 1, in: windows) == [0, 1, 2])
        #expect(WindowClassifier.relatedPopups(of: 3, in: windows) == [3])
        #expect(WindowClassifier.relatedPopups(of: 5, in: windows) == [])
    }

    @Test func findsTheParentWindowOfAPopup() {
        let windows = classifier.classify([
            window(1, layer: 101, frame: CGRect(x: 300, y: 120, width: 200, height: 200)),
            window(2, frame: CGRect(x: 900, y: 500, width: 400, height: 400), pid: 99, bundle: "com.example.other"),
            window(3, frame: CGRect(x: 1000, y: 600, width: 300, height: 300)),
            window(4, frame: CGRect(x: 0, y: 40, width: 800, height: 600)),
        ])
        #expect(WindowClassifier.parentWindow(of: 0, in: windows) == 3)
        let detached = classifier.classify([
            window(1, layer: 101, frame: CGRect(x: 300, y: 120, width: 200, height: 200)),
            window(2, frame: CGRect(x: 1000, y: 600, width: 300, height: 300)),
        ])
        #expect(WindowClassifier.parentWindow(of: 0, in: detached) == 1)
        #expect(WindowClassifier.parentWindow(of: 7, in: detached) == nil)
    }

    @Test func expandsCaptureBoundsForTheShadowWithinTheDisplay() {
        let bounds = WindowClassifier.captureBounds(
            of: [CGRect(x: 10, y: 40, width: 100, height: 100), CGRect(x: 110, y: 60, width: 50, height: 50)], shadowMargin: 20, within: display)
        #expect(bounds == CGRect(x: 0, y: 20, width: 180, height: 140))
        #expect(WindowClassifier.captureBounds(of: [], shadowMargin: 20, within: display) == nil)
        #expect(WindowClassifier.captureBounds(of: [CGRect(x: 5000, y: 0, width: 10, height: 10)], shadowMargin: 0, within: display) == nil)
    }
}
