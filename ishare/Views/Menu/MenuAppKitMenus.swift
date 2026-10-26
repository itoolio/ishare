import AppKit
import Defaults

@MainActor
enum MenuAppKitMenus {
    static func overflowMenu(openOnboarding: @escaping @MainActor () -> Void, openCommandPalette: @escaping @MainActor () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let captureText = ClosureMenuItem(title: "Capture Text".localized(), symbol: "text.viewfinder") {
            MenuController.shared.perform(afterDismissing: { await CaptureSession.captureImage(.TEXT) })
        }
        captureText.setAccessibilityIdentifier("menu.captureText")
        menu.addItem(captureText)
        let captureMenu = ClosureMenuItem(title: "Capture Menu…".localized(), symbol: "filemenu.and.cursorarrow") {
            MenuController.shared.perform(afterDismissing: { await CaptureSession.captureImage(.MENU) })
        }
        captureMenu.setAccessibilityIdentifier("menu.captureMenu")
        menu.addItem(captureMenu)
        let interval = ClosureMenuItem(title: (IntervalCapture.isRunning ? "Stop Interval Capture" : "Interval Capture").localized(), symbol: "stopwatch") {
            MenuController.shared.perform(afterDismissing: { await IntervalCapture.toggle() })
        }
        interval.setAccessibilityIdentifier("menu.intervalCapture")
        menu.addItem(interval)
        let translate = ClosureMenuItem(title: "Capture and Translate".localized(), symbol: "translate") {
            MenuController.shared.perform(afterDismissing: { await CaptureTranslateFlow.run() })
        }
        translate.setAccessibilityIdentifier("menu.captureTranslate")
        menu.addItem(translate)
        if CaptureAskFlow.isAvailable {
            let ask = ClosureMenuItem(title: "Capture and Ask".localized(), symbol: "sparkles") {
                MenuController.shared.perform(afterDismissing: { await CaptureAskFlow.run() })
            }
            ask.setAccessibilityIdentifier("menu.captureAsk")
            menu.addItem(ask)
        }
        if CaptureSession.isRecording {
            let marker = ClosureMenuItem(title: "Add Recording Marker".localized(), symbol: "flag") {
                AppModel.shared.recorder.addMarker()
            }
            marker.setAccessibilityIdentifier("menu.addMarker")
            menu.addItem(marker)
        }
        menu.addItem(notesItem())
        if InstantReplay.isRunning {
            menu.addItem(instantReplayItem())
        }
        if !UploadPresets.all.isEmpty {
            menu.addItem(presetsItem())
        }
        menu.addItem(.separator())
        menu.addItem(recentLinksItem())
        menu.addItem(ContinuityCameraImport.menuItem())
        let palette = ClosureMenuItem(title: "Command Palette…".localized(), symbol: "command", keyEquivalent: "k", handler: openCommandPalette)
        palette.setAccessibilityIdentifier("menu.commandPalette")
        menu.addItem(palette)
        menu.addItem(.separator())
        menu.addItem(
            ClosureMenuItem(title: "About ishare".localized()) {
                MenuController.shared.showAboutPanel()
            })
        #if GITHUB_RELEASE
            menu.addItem(
                ClosureMenuItem(title: "Check for Updates…".localized()) {
                    MenuController.shared.dismiss()
                    AppDelegate.shared.checkForUpdates()
                })
        #endif
        let onboarding = ClosureMenuItem(title: "Welcome Guide…".localized(), handler: openOnboarding)
        onboarding.setAccessibilityIdentifier("menu.onboarding")
        menu.addItem(onboarding)
        let whatsNew = ClosureMenuItem(title: "What’s New…".localized()) {
            MenuController.shared.dismiss()
            WhatsNewWindow.show()
        }
        whatsNew.setAccessibilityIdentifier("menu.whatsNew")
        menu.addItem(whatsNew)

        menu.addItem(.separator())
        menu.addItem(
            ClosureMenuItem(title: "Quit".localized(), keyEquivalent: "q") {
                NSApplication.shared.terminate(nil)
            })
        return menu
    }

    static func notesItem() -> NSMenuItem {
        let title = RecordingNotesController.shared.isVisible ? "Hide Notes" : "Show Notes"
        let item = ClosureMenuItem(title: title.localized(), symbol: "list.bullet.rectangle") {
            AppModel.shared.recorder.toggleNotes()
        }
        item.setAccessibilityIdentifier("menu.recordingNotes")
        return item
    }

    static func instantReplayItem() -> NSMenuItem {
        let item = ClosureMenuItem(title: "Save Instant Replay".localized(), symbol: "gobackward") {
            MenuController.shared.perform(afterDismissing: { await InstantReplay.shared.save() })
        }
        item.toolTip = "Instant replay is buffering the last moments of your main display".localized()
        item.setAccessibilityIdentifier("menu.instantReplay")
        return item
    }

    static func presetsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Capture with Preset".localized(), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        item.setAccessibilityIdentifier("menu.presets")
        let submenu = NSMenu(title: "Capture with Preset".localized())
        submenu.autoenablesItems = false
        for preset in UploadPresets.all {
            submenu.addItem(
                ClosureMenuItem(title: preset.name) {
                    MenuController.shared.perform(afterDismissing: { await UploadPresets.capture(preset, type: .REGION) })
                })
        }
        item.submenu = submenu
        return item
    }

    static func recentLinksItem(history: [HistoryItem] = Defaults[.uploadHistory]) -> NSMenuItem {
        let item = NSMenuItem(title: "Recent Links".localized(), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        item.setAccessibilityIdentifier("menu.recentLinks")
        let submenu = NSMenu(title: "Recent Links".localized())
        submenu.autoenablesItems = false
        let links = RecentLinks.links(from: history)
        if links.isEmpty {
            let empty = NSMenuItem(title: "No Recent Links".localized(), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for (index, link) in links.enumerated() {
                let copy = ClosureMenuItem(title: link.displayTitle) {
                    HistoryActions.copyURL(link.item)
                }
                copy.toolTip = String(format: "%@ — click to copy, ⌥-click to open".localized(), link.url)
                copy.setAccessibilityIdentifier("menu.recentLinks.\(index)")
                let open = ClosureMenuItem(title: String(format: "Open %@".localized(), link.displayTitle)) {
                    MenuController.shared.dismiss()
                    HistoryActions.open(link.item)
                }
                open.isAlternate = true
                open.keyEquivalentModifierMask = .option
                submenu.addItem(copy)
                submenu.addItem(open)
            }
            submenu.addItem(.separator())
            let hint = NSMenuItem(title: "Click to copy, ⌥-click to open".localized(), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            submenu.addItem(hint)
        }
        item.submenu = submenu
        return item
    }

    static func destinationMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = UploadDestinationSwitcher.current
        for (index, destination) in UploadDestinationSwitcher.destinations.enumerated() {
            if index == 1 {
                menu.addItem(.separator())
            }
            let item = ClosureMenuItem(title: UploadDestinationSwitcher.title(for: destination)) {
                UploadDestinationSwitcher.select(destination)
            }
            if case .builtIn = destination {
                item.image = ImgurIcon
            } else {
                item.image = NSImage(systemSymbolName: UploadDestinationSwitcher.symbol(for: destination), accessibilityDescription: nil)
            }
            item.state = destination == current ? .on : .off
            item.setAccessibilityIdentifier("menu.destination.\(UploadDestinationSwitcher.identifier(for: destination))")
            menu.addItem(item)
        }
        return menu
    }
}
