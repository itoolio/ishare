import AppKit
import Defaults
import Foundation
import Testing
@testable import ishare

struct CaptureShelfStateTests {
    func item(_ name: String, at seconds: TimeInterval = 0) -> CaptureShelfItem {
        CaptureShelfItem(fileURL: URL(fileURLWithPath: "/tmp/shelf/\(name)"), addedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func insertsNewestFirstInTheGivenOrder() {
        var state = CaptureShelfState()
        state.insert([item("a.png"), item("b.png")])
        state.insert([item("c.mov")])
        #expect(state.items.map(\.fileName) == ["c.mov", "b.png", "a.png"])
        #expect(state.items.first?.kind == .video)
        #expect(state.items.last?.kind == .image)
    }

    @Test func dedupesBySourceAndMovesTheExistingItemToTheFront() {
        var state = CaptureShelfState()
        let first = item("a.png")
        state.insert([first, item("b.png")])
        let result = state.insert([item("a.png")])
        #expect(state.items.count == 2)
        #expect(state.items.first?.id == first.id)
        #expect(result.inserted.isEmpty)
        #expect(result.duplicates.count == 1)
    }

    @Test func dedupesAFileDroppedBackFromTheShelfByItsStoredPath() {
        var state = CaptureShelfState()
        let stored = CaptureShelfItem(fileURL: URL(fileURLWithPath: "/tmp/cache/1/a.png"), sourceKey: "/Users/me/Desktop/a.png")
        state.insert([stored])
        state.insert([CaptureShelfItem(fileURL: URL(fileURLWithPath: "/tmp/cache/1/a.png"))])
        state.insert([CaptureShelfItem(fileURL: URL(fileURLWithPath: "/tmp/cache/2/a.png"), sourceKey: "/Users/me/Desktop/a.png")])
        #expect(state.items.map(\.id) == [stored.id])
    }

    @Test func capsTheShelfAndReportsEvictedItems() {
        var state = CaptureShelfState(capacity: 3)
        state.insert((0 ..< 3).map { item("\($0).png") })
        let result = state.insert([item("3.png"), item("4.png")])
        #expect(state.items.map(\.fileName) == ["4.png", "3.png", "2.png"])
        #expect(result.evicted.map(\.fileName) == ["1.png", "0.png"])
        #expect(result.inserted.map(\.fileName) == ["3.png", "4.png"])
    }

    @Test func reportsItemsThatAreEvictedInTheSameInsertion() {
        var state = CaptureShelfState(capacity: 2)
        let result = state.insert((0 ..< 4).map { item("\($0).png") })
        #expect(state.items.map(\.fileName) == ["3.png", "2.png"])
        #expect(result.evicted.map(\.fileName) == ["1.png", "0.png"])
        #expect(result.inserted.map(\.fileName) == ["2.png", "3.png"])
    }

    @Test func removesAndClearsItems() {
        var state = CaptureShelfState()
        let items = (0 ..< 3).map { item("\($0).png") }
        state.insert(items)
        #expect(state.remove([items[1].id]).map(\.id) == [items[1].id])
        #expect(state.items.count == 2)
        #expect(state.clear().count == 2)
        #expect(state.isEmpty)
    }

    @Test func dragsTheWholeSelectionInShelfOrderOnlyWhenTheItemIsSelected() {
        var state = CaptureShelfState()
        let items = (0 ..< 4).map { item("\($0).png") }
        state.insert(items)
        let selection: Set<UUID> = [items[0].id, items[2].id]
        #expect(state.dragItems(startingAt: items[0].id, selection: selection).map(\.fileName) == ["2.png", "0.png"])
        #expect(state.dragItems(startingAt: items[1].id, selection: selection).map(\.fileName) == ["1.png"])
        #expect(state.dragItems(startingAt: items[3].id, selection: [items[3].id]).map(\.fileName) == ["3.png"])
    }

    @Test func updatesALinkAfterUpload() {
        var state = CaptureShelfState()
        let item = item("a.png")
        state.insert([item])
        state.update(item.id) { $0.link = "https://example.com/a.png" }
        #expect(state.item(item.id)?.link == "https://example.com/a.png")
    }

    @Test func restoresInitialItemsInTheirOrder() {
        let state = CaptureShelfState(items: [item("new.png"), item("old.png")], capacity: 5)
        #expect(state.items.map(\.fileName) == ["new.png", "old.png"])
    }
}

struct CaptureShelfSelectionTests {
    let items = (0 ..< 5).map { CaptureShelfItem(fileURL: URL(fileURLWithPath: "/tmp/\($0).png")) }

    @Test func clickSelectsToggleAddsAndShiftExtends() {
        var selection = CaptureShelfSelection()
        selection.click(items[1].id, extending: false, toggling: false, in: items)
        #expect(selection.ids == [items[1].id])
        selection.click(items[3].id, extending: false, toggling: true, in: items)
        #expect(selection.ids == [items[1].id, items[3].id])
        selection.click(items[3].id, extending: false, toggling: true, in: items)
        #expect(selection.ids == [items[1].id])
        selection.click(items[1].id, extending: false, toggling: false, in: items)
        selection.click(items[4].id, extending: true, toggling: false, in: items)
        #expect(selection.ids == Set(items[1 ... 4].map(\.id)))
    }

    @Test func retainDropsRemovedItems() {
        var selection = CaptureShelfSelection()
        selection.click(items[0].id, extending: false, toggling: false, in: items)
        selection.click(items[2].id, extending: false, toggling: true, in: items)
        selection.retain(Array(items.dropFirst()))
        #expect(selection.ids == [items[2].id])
        selection.clear()
        #expect(selection.isEmpty)
    }
}

struct CaptureShelfGeometryTests {
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func placesTheShelfAtTheRememberedEdgeAndOffset() {
        let size = CGSize(width: 132, height: 300)
        let trailingTop = CaptureShelfGeometry.frame(size: size, placement: CaptureShelfPlacement(edge: .trailing, offset: 0), in: visible)
        #expect(trailingTop.maxX == visible.maxX - CaptureShelfGeometry.margin)
        #expect(trailingTop.maxY == visible.maxY - CaptureShelfGeometry.margin)
        let leadingBottom = CaptureShelfGeometry.frame(size: size, placement: CaptureShelfPlacement(edge: .leading, offset: 1), in: visible)
        #expect(leadingBottom.minX == visible.minX + CaptureShelfGeometry.margin)
        #expect(leadingBottom.minY == visible.minY + CaptureShelfGeometry.margin)
    }

    @Test func snapsADraggedFrameToTheNearestEdgeAndRoundTrips() {
        let size = CGSize(width: 132, height: 300)
        let dragged = CGRect(origin: CGPoint(x: 300, y: 400), size: size)
        let placement = CaptureShelfGeometry.placement(for: dragged, in: visible)
        #expect(placement.edge == .leading)
        let snapped = CaptureShelfGeometry.frame(size: size, placement: placement, in: visible)
        #expect(abs(snapped.minY - dragged.minY) <= 1)
        #expect(CaptureShelfGeometry.placement(for: CGRect(origin: CGPoint(x: 1000, y: 400), size: size), in: visible).edge == .trailing)
    }

    @Test func clampsOffsetsAndHeights() {
        let size = CGSize(width: 132, height: 300)
        let above = CaptureShelfGeometry.placement(for: CGRect(origin: CGPoint(x: 1300, y: 2000), size: size), in: visible)
        #expect(above.offset == 0)
        let below = CaptureShelfGeometry.placement(for: CGRect(origin: CGPoint(x: 1300, y: -500), size: size), in: visible)
        #expect(below.offset == 1)
        #expect(CaptureShelfGeometry.contentHeight(itemCount: 200, in: visible) <= visible.height - CaptureShelfGeometry.margin * 2)
        #expect(CaptureShelfGeometry.contentHeight(itemCount: 0, in: visible) == CaptureShelfGeometry.headerHeight + CaptureShelfGeometry.emptyHeight)
        #expect(CaptureShelfGeometry.contentHeight(itemCount: 2, in: visible) > CaptureShelfGeometry.contentHeight(itemCount: 1, in: visible))
    }

    @Test func keysScreensByDisplayUUIDWithAFallback() {
        #expect(CaptureShelfGeometry.screenKey(displayUUID: "ABC", localizedName: "Studio Display", frame: visible) == "ABC")
        #expect(CaptureShelfGeometry.screenKey(displayUUID: nil, localizedName: "Studio Display", frame: visible) == "Studio Display-1440x875")
    }
}

struct CaptureShelfStorageTests {
    @Test func storesCopiesAndOnlyRemovesItsOwnFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shelf-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = CaptureShelfStorage(directory: root.appending(path: "store", directoryHint: .isDirectory))
        let source = root.appending(path: "capture.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: source)
        let copy = try #require(storage.store(source))
        #expect(copy != source)
        #expect(storage.owns(copy))
        #expect(!storage.owns(source))
        #expect(storage.store(copy) == copy)
        storage.removeIfOwned(source)
        #expect(FileManager.default.fileExists(atPath: source.path))
        storage.removeIfOwned(copy)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    @MainActor @Test func modesAndSettingsAreTransferable() {
        #expect(CaptureShelfMode.off.collectsCaptures == false)
        #expect(CaptureShelfMode.afterCapture.showsAfterCapture)
        #expect(CaptureShelfMode.onDemand.collectsCaptures && !CaptureShelfMode.onDemand.showsAfterCapture)
        #expect(SettingsTransfer.preferenceNames.contains(Defaults.Keys.captureShelfMode.name))
        #expect(!SettingsTransfer.preferenceNames.contains(Defaults.Keys.captureShelfPlacements.name))
        #expect(CaptureShelfSettingsSection.searchEntries.allSatisfy { $0.pane == .capture })
    }

    @MainActor @Test func pasteboardWriterOffersAFilePromiseTheFileURLAndTheLink() {
        let item = CaptureShelfItem(fileURL: URL(fileURLWithPath: "/tmp/shot.png"), link: "https://example.com/shot.png")
        let writer = CaptureShelfPasteboardWriter(item: item)
        let types = writer.writableTypes(for: NSPasteboard(name: NSPasteboard.Name("ishare-shelf-tests")))
        #expect(types.contains(.fileURL))
        #expect(types.contains(.string))
        #expect(types.contains(NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")) || types.count > 3)
        #expect(writer.pasteboardPropertyList(forType: .string) as? String == "https://example.com/shot.png")
        #expect(writer.filePromiseProvider(writer, fileNameForType: "public.png") == "shot.png")
    }
}
