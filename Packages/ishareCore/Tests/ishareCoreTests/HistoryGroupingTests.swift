import Testing
@testable import ishareCore

struct HistoryGroupingTests {
    @Test func findsTheProjectInWindowTitles() {
        #expect(HistoryGrouping.project(fromTitle: "ishare — ScreenRecorder.swift", appName: "Xcode") == "ishare")
        #expect(HistoryGrouping.project(fromTitle: "main.ts — website — Visual Studio Code", appName: "Visual Studio Code") == "website")
        #expect(HistoryGrouping.project(fromTitle: "Release checklist - Google Docs - Google Chrome", appName: "Google Chrome") == "Google Docs")
        #expect(HistoryGrouping.project(fromTitle: "Figma", appName: "Figma") == nil)
        #expect(HistoryGrouping.project(fromTitle: nil, appName: "Safari") == nil)
        #expect(HistoryGrouping.project(fromTitle: "Untitled", appName: "TextEdit") == "Untitled")
    }
}
