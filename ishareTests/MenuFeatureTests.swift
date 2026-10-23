import AppKit
import Foundation
import Testing
@testable import ishare

struct MenuLayoutTests {
    @Test func normalizesOrderByDroppingDuplicatesAndAppendingMissingSections() {
        #expect(MenuLayout.normalized([.footer, .capture, .footer]) == [.footer, .capture, .record, .afterCapture, .recentUploads])
        #expect(MenuLayout.normalized([]) == MenuSection.allCases)
    }

    @Test func movesSectionsWithinBounds() {
        let layout = MenuLayout()
        #expect(layout.moving(.record, by: -1).order == [.record, .capture, .afterCapture, .recentUploads, .footer])
        #expect(layout.moving(.capture, by: -1) == layout)
        #expect(layout.moving(.capture, by: 10).order.last == .capture)
    }

    @Test func hidesAndShowsSections() {
        let hidden = MenuLayout().setting(.afterCapture, visible: false)
        #expect(hidden.visibleSections == [.capture, .record, .recentUploads, .footer])
        #expect(!hidden.isVisible(.afterCapture))
        #expect(hidden.setting(.afterCapture, visible: true).visibleSections == MenuSection.allCases)
    }

    @Test func compactDensityShrinksTiles() {
        let comfortable = MenuDensity.comfortable.metrics
        let compact = MenuDensity.compact.metrics
        #expect(compact.tileHeight < comfortable.tileHeight)
        #expect(compact.wideHeight < comfortable.wideHeight)
        #expect(compact.stackSpacing < comfortable.stackSpacing)
        #expect(comfortable.tileHeight == 58)
    }

    @Test func highContrastFollowsTheUserOrTheSystem() {
        #expect(MenuContrast.resolve(userPreference: false, systemIncreaseContrast: false) == .standard)
        #expect(MenuContrast.resolve(userPreference: true, systemIncreaseContrast: false) == .high)
        #expect(MenuContrast.resolve(userPreference: false, systemIncreaseContrast: true) == .high)
        #expect(MenuContrast.high.fillOpacity > MenuContrast.standard.fillOpacity)
        #expect(MenuContrast.high.borderOpacity > MenuContrast.standard.borderOpacity)
    }

    @Test func themesMapToAppearances() {
        #expect(MenuTheme.system.appearanceName == nil)
        #expect(MenuTheme.light.appearanceName == .aqua)
        #expect(MenuTheme.dark.appearanceName == .darkAqua)
    }
}

struct MenuFocusLayoutTests {
    @Test func followsTheSectionOrder() {
        let rows = MenuFocusLayout.rows(sections: [.footer, .capture], isRecording: false, chipCount: 3, recentCount: 2)
        #expect(rows == [[.destination, .settings, .more], [.footer(0), .footer(1)], [.capture(0), .capture(1), .capture(2), .capture(3)]])
    }

    @Test func includesRecentUploadsOnlyWhenThereAreAny() {
        let empty = MenuFocusLayout.rows(sections: [.recentUploads], isRecording: false, chipCount: 0, recentCount: 0)
        #expect(empty == [[.destination, .settings, .more]])
        let filled = MenuFocusLayout.rows(sections: [.recentUploads, .record, .afterCapture], isRecording: true, chipCount: 2, recentCount: 2)
        #expect(filled == [[.destination, .settings, .more], [.recent(0), .recent(1), .history], [.stopRecording], [.chip(0), .chip(1)]])
    }

    @Test func placesTheDonateButtonBetweenTheDestinationAndSettings() {
        #expect(MenuFocusLayout.headerRow(showsDonate: true) == [.destination, .donate, .settings, .more])
        let rows = MenuFocusLayout.rows(sections: [], isRecording: false, chipCount: 0, recentCount: 0, showsDonate: true)
        #expect(MenuFocusNavigator.move(from: .destination, .right, in: rows) == .donate)
    }

    @Test func recognisesTheRecentLinksKey() {
        #expect(MenuFocusNavigator.isRecentLinksKey("l"))
        #expect(MenuFocusNavigator.isRecentLinksKey("L"))
        #expect(!MenuFocusNavigator.isRecentLinksKey("k"))
    }
}

struct CommandPaletteTests {
    @Test func scoresSubstringsAboveSubsequences() throws {
        let substring = try #require(FuzzyMatcher.score("region", in: "Capture Region"))
        let subsequence = try #require(FuzzyMatcher.score("cprg", in: "Capture Region"))
        #expect(substring > subsequence)
        #expect(FuzzyMatcher.score("xyz", in: "Capture Region") == nil)
        #expect(FuzzyMatcher.score("", in: "Anything") == 0)
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(FuzzyMatcher.score("CAPTURE", in: "capture") != nil)
        #expect(FuzzyMatcher.score("cafe", in: "Café") != nil)
    }

    @Test @MainActor func ranksCommandsByBestMatch() {
        let commands = [
            AppCommand(id: "a", title: "Record Screen", keywords: ["video"], symbol: "record.circle") {},
            AppCommand(id: "b", title: "Capture Screen", keywords: ["screenshot"], symbol: "display") {},
            AppCommand(id: "c", title: "Quit", keywords: ["exit"], symbol: "power") {},
        ]
        let identity: (String) -> String = { $0 }
        #expect(AppCommandRegistry.matches(for: "", in: commands, localize: identity).map(\.id) == ["a", "b", "c"])
        #expect(AppCommandRegistry.matches(for: "capture", in: commands, localize: identity).map(\.id) == ["b"])
        #expect(AppCommandRegistry.matches(for: "exit", in: commands, localize: identity).map(\.id) == ["c"])
        #expect(AppCommandRegistry.matches(for: "screen", in: commands, localize: identity).map(\.id).sorted() == ["a", "b"])
        #expect(AppCommandRegistry.matches(for: "zzz", in: commands, localize: identity).isEmpty)
    }

    @Test @MainActor func registryCoversEveryKindOfAction() {
        let ids = AppCommand.all().map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ["capture.region", "capture.window", "capture.screen", "capture.scrolling", "record.screen", "record.gif",
                   "editor.open", "upload.clipboard", "history.open", "destination.imgur", "app.about", "app.quit"] {
            #expect(ids.contains(id), "\(id)")
        }
        #expect(SettingsPane.allCases.allSatisfy { ids.contains("settings.\($0.rawValue)") })
    }

    @Test @MainActor func destinationSwitcherCycles() {
        let destinations: [UploadDestination] = [.builtIn(.IMGUR), .custom(UUID())]
        #expect(UploadDestinationSwitcher.next(after: destinations[0], in: destinations) == destinations[1])
        #expect(UploadDestinationSwitcher.next(after: destinations[1], in: destinations) == destinations[0])
        #expect(UploadDestinationSwitcher.next(after: .custom(nil), in: destinations) == destinations[0])
        #expect(UploadDestinationSwitcher.next(after: destinations[0], in: []) == nil)
    }
}

struct RecentLinksTests {
    @Test func keepsTheNewestUniqueLinksUpToTheLimit() {
        let history = (0 ..< 30).map { HistoryItem(fileUrl: "https://i.example.com/\($0 % 25).png") } + [HistoryItem(fileUrl: nil), HistoryItem(fileUrl: " ")]
        let links = RecentLinks.links(from: history)
        #expect(links.count == 20)
        #expect(links.first?.url == "https://i.example.com/0.png")
        #expect(Set(links.map(\.url)).count == 20)
    }

    @Test func showsHostAndPath() {
        #expect(RecentLink(item: HistoryItem(), url: "https://i.example.com/a.png?x=1").displayTitle == "i.example.com/a.png")
        #expect(RecentLink(item: HistoryItem(), url: "https://example.com/").displayTitle == "example.com")
        #expect(RecentLink(item: HistoryItem(), url: "not a url").displayTitle == "not a url")
    }
}

struct ToastPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func stacksDownwardFromTopCorners() {
        let frames = ToastPlacement.frames(for: [100, 50], width: 300, in: screen, corner: .topLeft, margin: 16, spacing: 10)
        #expect(frames == [CGRect(x: 16, y: 684, width: 300, height: 100), CGRect(x: 16, y: 624, width: 300, height: 50)])
    }

    @Test func stacksUpwardFromBottomCorners() {
        let frames = ToastPlacement.frames(for: [100, 50], width: 300, in: screen, corner: .bottomRight, margin: 16, spacing: 10)
        #expect(frames == [CGRect(x: 684, y: 16, width: 300, height: 100), CGRect(x: 684, y: 126, width: 300, height: 50)])
    }

    @Test func resolvesTheConfiguredScreen() {
        let left = ToastScreenCandidate(displayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 90))
        let right = ToastScreenCandidate(displayID: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 100, y: 0, width: 100, height: 90))
        let screens = [left, right]
        let pointer = CGPoint(x: 150, y: 50)
        #expect(ToastPlacement.resolve(.main, screens: screens, main: left, pointer: pointer, capturedDisplayID: 2) == left)
        #expect(ToastPlacement.resolve(.pointer, screens: screens, main: left, pointer: pointer, capturedDisplayID: nil) == right)
        #expect(ToastPlacement.resolve(.capturedContent, screens: screens, main: right, pointer: CGPoint(x: 10, y: 10), capturedDisplayID: 1) == left)
        #expect(ToastPlacement.resolve(.capturedContent, screens: screens, main: left, pointer: pointer, capturedDisplayID: nil) == right)
        #expect(ToastPlacement.resolve(.pointer, screens: screens, main: nil, pointer: CGPoint(x: -50, y: 0), capturedDisplayID: nil) == left)
    }
}

struct HistoryTimelineTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ day: Int, hour: Int = 12, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func groupsByDayWithRelativeTitles() {
        let now = date(23, hour: 18)
        let items = [
            HistoryItem(fileUrl: "a", date: date(23, hour: 9)),
            HistoryItem(fileUrl: "b", date: date(23, hour: 8)),
            HistoryItem(fileUrl: "c", date: date(22)),
            HistoryItem(fileUrl: "d", date: date(19)),
            HistoryItem(fileUrl: "e", date: date(1)),
            HistoryItem(fileUrl: "f", date: date(3, year: 2025)),
            HistoryItem(fileUrl: "g"),
        ]
        let sections = HistoryTimeline.sections(for: items, now: now, calendar: calendar, locale: Locale(identifier: "en_US"), localize: { $0 })
        #expect(sections.map(\.items.count) == [2, 1, 1, 1, 1, 1])
        #expect(sections[0].title == "Today")
        #expect(sections[1].title == "Yesterday")
        #expect(sections[2].title == "Monday")
        #expect(sections[3].title.contains("Oct"))
        #expect(sections[3].title.contains("1"))
        #expect(sections[4].title.contains("2025"))
        #expect(sections[5].title == "Undated")
        #expect(sections[0].items.map(\.fileUrl) == ["a", "b"])
    }

    @Test func keepsSectionsNewestFirstEvenWhenInputIsUnordered() {
        let now = date(23)
        let items = [HistoryItem(fileUrl: "old", date: date(20)), HistoryItem(fileUrl: "new", date: date(23))]
        let sections = HistoryTimeline.sections(for: items, now: now, calendar: calendar, locale: Locale(identifier: "en_US"), localize: { $0 })
        #expect(sections.map { $0.items[0].fileUrl } == ["new", "old"])
    }
}

struct HistorySelectionTests {
    let items = (0 ..< 5).map { HistoryItem(fileUrl: "https://x.test/\($0)") }

    @Test func plainClickSelectsOnlyTheItem() {
        var selection = HistorySelection()
        selection.click(items[1], modifier: .none, in: items)
        selection.click(items[2], modifier: .none, in: items)
        #expect(selection.ordered(in: items) == [items[2]])
    }

    @Test func commandClickToggles() {
        var selection = HistorySelection()
        selection.click(items[0], modifier: .toggle, in: items)
        selection.click(items[3], modifier: .toggle, in: items)
        #expect(selection.ordered(in: items) == [items[0], items[3]])
        selection.click(items[0], modifier: .toggle, in: items)
        #expect(selection.ordered(in: items) == [items[3]])
    }

    @Test func shiftClickExtendsFromTheAnchor() {
        var selection = HistorySelection()
        selection.click(items[3], modifier: .none, in: items)
        selection.click(items[1], modifier: .extend, in: items)
        #expect(selection.ordered(in: items) == Array(items[1 ... 3]))
        var fresh = HistorySelection()
        fresh.click(items[2], modifier: .extend, in: items)
        #expect(fresh.ordered(in: items) == [items[2]])
    }

    @Test func selectAllRetainAndClear() {
        var selection = HistorySelection()
        selection.selectAll(items)
        #expect(selection.count == 5)
        selection.retain(Array(items.prefix(2)))
        #expect(selection.ordered(in: items) == Array(items.prefix(2)))
        selection.clear()
        #expect(selection.isEmpty)
    }

    @Test func collectsLinks() {
        #expect(HistorySelection.links(for: [HistoryItem(fileUrl: "a"), HistoryItem(), HistoryItem(fileUrl: " ")]) == ["a"])
    }
}

struct UploadUndoTests {
    @Test func offersUndoForTenSecondsForDeletableUploads() {
        let now = Date()
        let fresh = HistoryItem(fileUrl: "https://x.test/a", deletionUrl: "https://x.test/delete", date: now.addingTimeInterval(-3))
        #expect(UploadUndo.deadline(for: fresh, now: now) == fresh.date!.addingTimeInterval(10))
        let stale = HistoryItem(fileUrl: "https://x.test/a", deletionUrl: "https://x.test/delete", date: now.addingTimeInterval(-11))
        #expect(UploadUndo.deadline(for: stale, now: now) == nil)
        let undeletable = HistoryItem(fileUrl: "https://x.test/a", date: now)
        #expect(UploadUndo.deadline(for: undeletable, now: now) == nil)
        #expect(UploadUndo.deadline(for: nil, now: now) == nil)
    }

    @Test @MainActor func toastModelTracksTheUndoWindow() {
        let item = HistoryItem(fileUrl: "https://x.test/a", deletionUrl: "https://x.test/delete", date: Date())
        let model = ToastModel(fileURL: URL(fileURLWithPath: "/tmp/a.png"), isImage: true, historyItem: item)
        #expect(model.canUndo)
        model.historyItem = nil
        #expect(!model.canUndo)
    }

    @Test @MainActor func explicitlyResolvedUploadsIgnoreIdleActivity() {
        let model = ToastModel(fileURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).png"), isImage: true)
        model.followUpload(resolvesExplicitly: true)
        #expect(model.isAwaitingUpload)
        model.resolveUpload()
        #expect(!model.isAwaitingUpload)
    }
}

struct ResultPresentationTests {
    @Test func presentationFlags() {
        #expect(ResultPresentation.toast.showsToast && !ResultPresentation.toast.postsNotification)
        #expect(!ResultPresentation.notification.showsToast && ResultPresentation.notification.postsNotification)
        #expect(ResultPresentation.both.showsToast && ResultPresentation.both.postsNotification)
    }

    @Test func payloadRoundTripsAndPicksACategory() {
        let payload = ResultNotificationPayload(url: "https://x.test/a.png", path: "/tmp/a.png")
        #expect(ResultNotificationPayload(userInfo: payload.userInfo) == payload)
        #expect(payload.categoryIdentifier == ResultNotifier.editableCategory)
        #expect(ResultNotificationPayload(url: "https://x.test/a.mp4", path: "/tmp/a.mp4").categoryIdentifier == ResultNotifier.linkCategory)
        #expect(ResultNotificationPayload(url: "https://x.test/a", path: nil).categoryIdentifier == ResultNotifier.linkCategory)
    }
}

struct ContinuityCameraTests {
    @Test func acceptsOnlyImageReturnTypes() {
        #expect(ContinuityCameraImport.accepts(sendType: nil, returnType: .png))
        #expect(ContinuityCameraImport.accepts(sendType: nil, returnType: .tiff))
        #expect(!ContinuityCameraImport.accepts(sendType: nil, returnType: .string))
        #expect(!ContinuityCameraImport.accepts(sendType: .png, returnType: .png))
        #expect(!ContinuityCameraImport.accepts(sendType: nil, returnType: nil))
    }

    @Test func readsImagesFromThePasteboard() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 40, height: 30), hue: 0.2, title: "C"))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ishare.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: CGSize(width: 40, height: 30))])
        #expect(ContinuityCameraImport.image(from: pasteboard) != nil)
    }
}
