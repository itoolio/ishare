import AppKit
import Defaults
import ishareCore
import SwiftUI

struct FeatureTourStop: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let commandID: String?
}

@MainActor
enum FeatureTour {
    static let tourID = "5.7"
    static let introducedIn = [5, 7]
    private static var window: NSWindow?

    static let stops: [FeatureTourStop] = [
        FeatureTourStop(
            id: "replay", symbol: "clock.arrow.circlepath", title: "Screenshot Replay",
            detail: "Missed the moment? Keep the last seconds of your screen and pick the frame you wanted.", commandID: "capture.replay"),
        FeatureTourStop(
            id: "web", symbol: "globe", title: "Full-Page Web Captures",
            detail: "Capture a whole web page from its address, without scrolling, at desktop or phone width.", commandID: "capture.web"),
        FeatureTourStop(
            id: "spaces", symbol: "rectangle.3.group", title: "Windows on Other Spaces",
            detail: "Capture a window or full-screen app on another Space without switching to it.", commandID: "capture.otherSpace"),
        FeatureTourStop(
            id: "snapping", symbol: "rectangle.dashed", title: "Snapping Selections",
            detail: "Region selections snap to window edges, buttons and panels. Hold ⌃ to draw freely.", commandID: "capture.region"),
        FeatureTourStop(
            id: "follow", symbol: "cursorarrow.motionlines", title: "Follow the Pointer",
            detail: "Record an area that pans with your pointer, with live captions and separate tracks for editing.", commandID: "record.follow"),
        FeatureTourStop(
            id: "editor", symbol: "square.on.circle", title: "A Bigger Editor",
            detail: "Shapes, measurements, a grid and rulers, align and distribute, tabs, and text translated in place.", commandID: "editor.open"),
        FeatureTourStop(
            id: "automation", symbol: "terminal", title: "Automation and AI",
            detail: "Use ishare from AppleScript, Shortcuts, the command line, watch-folder chains and AI assistants through MCP.", commandID: "settings.advanced"),
    ]

    static func presentIfNeeded(lastLaunched: String?) -> Bool {
        guard
            FeatureTourPolicy.shouldPresent(
                tourID: tourID, introducedIn: introducedIn, seenTourID: Defaults[.seenFeatureTour], lastLaunched: lastLaunched.flatMap(AppVersion.init)?.components,
                hasCompletedOnboarding: Defaults[.hasCompletedOnboarding], isSuppressed: WhatsNew.isSuppressed)
        else { return false }
        show()
        return true
    }

    static func show() {
        Defaults[.seenFeatureTour] = tourID
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "What’s New in ishare".localized()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FeatureTourView(stops: stops, onTry: tryStop, onClose: close))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    static func close() {
        window?.close()
        window = nil
    }

    private static func tryStop(_ stop: FeatureTourStop) {
        close()
        guard let id = stop.commandID, let command = AppCommand.all().first(where: { $0.id == id }) else { return }
        command.perform()
    }
}

struct FeatureTourView: View {
    let stops: [FeatureTourStop]
    let onTry: (FeatureTourStop) -> Void
    let onClose: () -> Void
    @State private var index = 0

    var body: some View {
        let stop = stops[index]
        VStack(spacing: 18) {
            Image(systemName: stop.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.menuAccent.gradient))
                .padding(.top, 36)
            VStack(spacing: 8) {
                Text(stop.title.localized())
                    .font(.system(size: 21, weight: .bold))
                Text(stop.detail.localized())
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            .id(stop.id)
            if stop.commandID != nil {
                Button("Try It".localized()) { onTry(stop) }
                    .accessibilityIdentifier("tour.try")
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(stops.indices, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? Color.menuAccent : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            HStack {
                Button("Skip Tour".localized(), action: onClose)
                    .accessibilityIdentifier("tour.skip")
                Spacer()
                if index > 0 {
                    Button("Back".localized()) { index -= 1 }
                }
                Button(index == stops.count - 1 ? "Done".localized() : "Next".localized()) {
                    if index == stops.count - 1 { onClose() } else { index += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("tour.next")
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 520, height: 400)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.window")
    }
}
