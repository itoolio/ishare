import AppKit
import Defaults
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openCommandPalette = Self("openCommandPalette")
}

struct AppCommand: Identifiable {
    let id: String
    let title: String
    var keywords: [String] = []
    let symbol: String
    let perform: @MainActor () -> Void
}

struct AppCommandMatch: Identifiable {
    let command: AppCommand
    let score: Int

    var id: String { command.id }
}

enum FuzzyMatcher {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(normalized(query).filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let text = normalized(candidate)
        let haystack = Array(text)
        if let range = text.range(of: String(needle)) {
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            return 1000 - offset * 2 - (haystack.count - needle.count)
        }
        var score = 0
        var needleIndex = 0
        var previousMatch: Int?
        for (index, character) in haystack.enumerated() where needleIndex < needle.count {
            guard character == needle[needleIndex] else { continue }
            score += 10
            if index == 0 || !haystack[index - 1].isLetter && !haystack[index - 1].isNumber {
                score += 15
            }
            if let previousMatch, previousMatch == index - 1 {
                score += 8
            } else if let previousMatch {
                score -= min(index - previousMatch, 6)
            }
            previousMatch = index
            needleIndex += 1
        }
        return needleIndex == needle.count ? score : nil
    }

    static func bestScore(_ query: String, in candidates: [String]) -> Int? {
        candidates.compactMap { score(query, in: $0) }.max()
    }
}

@MainActor
enum AppCommandRegistry {
    static func matches(for query: String, in commands: [AppCommand], localize: (String) -> String = { $0.localized() }) -> [AppCommandMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return commands.map { AppCommandMatch(command: $0, score: 0) }
        }
        let scored = commands.enumerated().compactMap { index, command -> (Int, AppCommandMatch)? in
            let title = localize(command.title)
            let titleScore = FuzzyMatcher.score(trimmed, in: title).map { $0 + 50 }
            let keywordScore = FuzzyMatcher.bestScore(trimmed, in: [command.title] + command.keywords + command.keywords.map(localize))
            guard let best = [titleScore, keywordScore].compactMap({ $0 }).max() else { return nil }
            return (index, AppCommandMatch(command: command, score: best))
        }
        return scored
            .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
            .map(\.1)
    }
}

extension AppCommand {
    @MainActor static func all() -> [AppCommand] {
        captureCommands() + recordingCommands() + toolCommands() + destinationCommands() + settingsCommands() + appCommands()
    }

    @MainActor private static func afterDismissing(_ action: @escaping @MainActor () async -> Void) -> @MainActor () -> Void {
        { MenuController.shared.perform(afterDismissing: action) }
    }

    @MainActor private static func captureCommands() -> [AppCommand] {
        [
            AppCommand(id: "capture.region", title: "Capture Region", keywords: ["screenshot", "area", "selection"], symbol: "rectangle.dashed",
                       perform: afterDismissing { await CaptureSession.captureImage(.REGION) }),
            AppCommand(id: "capture.window", title: "Capture Window", keywords: ["screenshot", "app"], symbol: "macwindow",
                       perform: afterDismissing { await CaptureSession.captureImage(.WINDOW) }),
            AppCommand(id: "capture.screen", title: "Capture Screen", keywords: ["screenshot", "display", "fullscreen"], symbol: "display",
                       perform: afterDismissing { await CaptureSession.captureImage(.SCREEN) }),
            AppCommand(id: "capture.scrolling", title: "Scrolling Capture", keywords: ["screenshot", "long", "scroll"], symbol: "arrow.up.and.down.text.horizontal",
                       perform: afterDismissing { await CaptureSession.captureImage(.SCROLLING) }),
            AppCommand(id: "capture.lastRegion", title: "Capture Last Region", keywords: ["screenshot", "repeat", "again"], symbol: "arrow.counterclockwise",
                       perform: afterDismissing { await CaptureSession.captureImage(.LAST_REGION) }),
            AppCommand(id: "capture.text", title: "Capture Text", keywords: ["ocr", "recognize", "copy text"], symbol: "text.viewfinder",
                       perform: afterDismissing { await CaptureSession.captureImage(.TEXT) }),
            AppCommand(id: "capture.timer", title: "Capture Region in 5 Seconds", keywords: ["timer", "delay", "countdown", "self-timer"], symbol: "timer",
                       perform: afterDismissing { await CaptureSession.captureImage(.REGION, options: CaptureOptions(delay: 5)) }),
            AppCommand(id: "capture.interval", title: IntervalCapture.isRunning ? "Stop Interval Capture" : "Interval Capture", keywords: ["burst", "time-lapse", "repeat"], symbol: "stopwatch",
                       perform: afterDismissing { await IntervalCapture.toggle() }),
            AppCommand(id: "capture.translate", title: "Capture and Translate", keywords: ["translation", "ocr", "language", "text"], symbol: "translate",
                       perform: afterDismissing { await CaptureTranslateFlow.run() }),
        ] + askCommands() + presetCommands()
    }

    @MainActor private static func askCommands() -> [AppCommand] {
        guard CaptureAskFlow.isAvailable else { return [] }
        return [
            AppCommand(id: "capture.ask", title: "Capture and Ask", keywords: ["apple intelligence", "question", "describe", "summarize", "explain"], symbol: "sparkles",
                       perform: afterDismissing { await CaptureAskFlow.run() }),
        ]
    }

    @MainActor private static func presetCommands() -> [AppCommand] {
        UploadPresets.all.map { preset in
            AppCommand(id: "preset.\(preset.id.uuidString)", title: String(format: "Capture with %@".localized(), preset.name), keywords: ["preset", "upload", preset.name], symbol: "square.stack.3d.up",
                       perform: afterDismissing { await UploadPresets.capture(preset, type: .REGION) })
        }
    }

    @MainActor private static func recordingCommands() -> [AppCommand] {
        if CaptureSession.isRecording {
            return [
                AppCommand(id: "record.stop", title: "Stop Recording", keywords: ["video", "end"], symbol: "stop.fill") {
                    MenuController.shared.dismiss()
                    CaptureSession.stopRecording()
                },
                AppCommand(id: "record.marker", title: "Add Recording Marker", keywords: ["chapter", "bookmark", "marker"], symbol: "flag") {
                    MenuController.shared.dismiss()
                    AppDelegate.shared.screenRecorder.addMarker()
                },
            ] + recordingExtraCommands()
        }
        return recordingExtraCommands() + [
            AppCommand(id: "record.screen", title: "Record Screen", keywords: ["video", "movie", "screencast"], symbol: "record.circle",
                       perform: afterDismissing { CaptureSession.toggleRecording() }),
            AppCommand(id: "record.region", title: "Record Region", keywords: ["video", "area"], symbol: "rectangle.dashed.badge.record",
                       perform: afterDismissing { CaptureSession.toggleRecording(region: true) }),
            AppCommand(id: "record.gif", title: "Record GIF", keywords: ["animation", "video"], symbol: "photo.stack",
                       perform: afterDismissing { CaptureSession.toggleRecording(gif: true) }),
            AppCommand(id: "record.regionGif", title: "Record Region as GIF", keywords: ["animation", "area"], symbol: "photo.stack",
                       perform: afterDismissing { CaptureSession.toggleRecording(gif: true, region: true) }),
        ]
    }

    @MainActor private static func recordingExtraCommands() -> [AppCommand] {
        var commands = [
            AppCommand(id: "record.notes", title: RecordingNotesController.shared.isVisible ? "Hide Notes" : "Show Notes", keywords: ["teleprompter", "script", "notes"], symbol: "list.bullet.rectangle") {
                MenuController.shared.dismiss()
                AppDelegate.shared.screenRecorder.toggleNotes()
            },
        ]
        if InstantReplay.isRunning {
            commands.append(AppCommand(id: "record.instantReplay", title: "Save Instant Replay", keywords: ["replay", "buffer", "clip", "last"], symbol: "gobackward",
                                       perform: afterDismissing { await InstantReplay.shared.save() }))
        }
        return commands
    }

    @MainActor private static func toolCommands() -> [AppCommand] {
        [
            AppCommand(id: "editor.open", title: "Edit Image…", keywords: ["editor", "annotate", "markup"], symbol: "pencil.and.scribble",
                       perform: afterDismissing { await ImageEditor.chooseAndEdit() }),
            AppCommand(id: "upload.clipboard", title: "Upload Clipboard", keywords: ["pasteboard", "paste"], symbol: "doc.on.clipboard",
                       perform: afterDismissing { await AppState.uploadPasteboard() }),
            AppCommand(id: "history.open", title: "Open History Window", keywords: ["uploads", "recent", "links"], symbol: "square.grid.2x2") {
                MenuController.shared.dismiss()
                openHistoryWindow(uploadHistory: Defaults[.uploadHistory])
            },
        ]
    }

    @MainActor private static func destinationCommands() -> [AppCommand] {
        UploadDestinationSwitcher.destinations.map { destination in
            let name = UploadDestinationSwitcher.title(for: destination)
            return AppCommand(
                id: "destination.\(UploadDestinationSwitcher.identifier(for: destination))",
                title: String(format: "Switch to %@".localized(), name),
                keywords: ["uploader", "destination", name],
                symbol: "icloud.and.arrow.up"
            ) {
                UploadDestinationSwitcher.select(destination)
            }
        }
    }

    @MainActor private static func settingsCommands() -> [AppCommand] {
        SettingsPane.allCases.map { pane in
            AppCommand(
                id: "settings.\(pane.rawValue)",
                title: String(format: "%@ Settings".localized(), pane.title.localized()),
                keywords: ["settings", "preferences", pane.title],
                symbol: pane.symbol
            ) {
                MenuController.shared.openSettings(pane: pane)
            }
        }
    }

    @MainActor private static func appCommands() -> [AppCommand] {
        [
            AppCommand(id: "app.about", title: "About ishare", keywords: ["version", "credits"], symbol: "info.circle") {
                MenuController.shared.showAboutPanel()
            },
            AppCommand(id: "app.quit", title: "Quit", keywords: ["exit", "close"], symbol: "power") {
                NSApplication.shared.terminate(nil)
            },
        ]
    }
}
