import AppKit
import Foundation
import Testing
@testable import ishare

struct HistoryPreviewTests {
    private func localItem(named name: String) throws -> HistoryItem {
        let url = try Fixtures.temporaryFile(named: name, contents: Data([0x89, 0x50, 0x4E, 0x47]))
        return HistoryItem(fileUrl: "https://example.com/\(name)", localPath: url.path)
    }

    @Test func previewsLocalFilesInVisibleOrderAndSkipsMissingOnes() throws {
        let first = try localItem(named: "first.png")
        let missing = HistoryItem(fileUrl: "https://example.com/gone.png", localPath: "/nonexistent/gone.png")
        let second = try localItem(named: "second.png")
        let urls = HistoryPreview.urls(for: [first, missing, second])
        #expect(urls.map(\.lastPathComponent) == ["first.png", "second.png"])
    }

    @Test func startsAtTheSelectionOrTheFirstVisibleItem() throws {
        let first = try localItem(named: "a.png")
        let second = try localItem(named: "b.png")
        #expect(HistoryPreview.startURL(selected: [second], visible: [first, second])?.lastPathComponent == "b.png")
        #expect(HistoryPreview.startURL(selected: [], visible: [first, second])?.lastPathComponent == "a.png")
    }

    @Test func cachesRemoteItemsUnderAStableName() {
        let item = HistoryItem(fileUrl: "https://example.com/shot.png")
        let first = HistoryPreview.cachedRemoteURL(for: item)
        #expect(first == HistoryPreview.cachedRemoteURL(for: item))
        #expect(first?.lastPathComponent.hasSuffix("-shot.png") == true)
        #expect(HistoryPreview.cachedRemoteURL(for: HistoryItem(fileUrl: "file:///tmp/x.png")) == nil)
    }
}

@MainActor
struct HistoryQuickLookTests {
    func space(in window: NSWindow, modifiers: NSEvent.ModifierFlags = [], repeated: Bool = false) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeated, keyCode: 49)
    }

    @Test func ignoresSpaceOutsideTheKeyHistoryWindow() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let event = try #require(space(in: window))
        #expect(!HistoryQuickLook.shouldToggle(on: event, in: window))
        let other = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        #expect(!HistoryQuickLook.shouldToggle(on: event, in: other))
    }

    @Test func doesNothingWithoutPreviewableFiles() {
        HistoryQuickLook.shared.toggle(urls: [], start: nil)
        #expect(!HistoryQuickLook.shared.isVisible)
    }
}
