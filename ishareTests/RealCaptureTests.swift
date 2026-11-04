import AppKit
import ishareCore
import Testing
@testable import ishare

@MainActor
final class OrderRecorder {
    var log = SelectionOrderLog(expectsFreezeFrames: true)
    var overlayVisibleWhenShown = false
}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ISHARE_REAL_CAPTURE"] == "1", "Runs only where screen recording is allowed"))
struct RealCaptureTests {
    @Test func capturesRealFramesOfEveryDisplay() async throws {
        #expect(ScreenshotEngine.hasPermission)
        let content = try await ScreenshotEngine.shareableContent()
        let backdrops = await ScreenshotEngine.backdrops(for: content)
        #expect(backdrops.count == content.displays.count)
        for display in content.displays {
            let image = try #require(backdrops[display.displayID])
            #expect(image.width >= display.width)
            let pixels = try #require(PixelBuffer(image))
            #expect(pixels.variance(in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)) > 1)
        }
    }

    @Test func freezesTheScreenBeforeTheSelectorAppears() async throws {
        let content = try await ScreenshotEngine.shareableContent()
        let loader = SelectionBackdropLoader(content: content, blursPrivateApps: false, mode: .frozen)
        let recorder = OrderRecorder()
        let backdrops = await loader.captureBeforeSelectionIfFrozen()
        recorder.log.record(.freezeFramesReady(at: ProcessInfo.processInfo.systemUptime))
        #expect(!backdrops.isEmpty)
        var options = RegionSelector.Options(backdrops: backdrops, allowsFreezeToggle: true, freezeMode: .frozen)
        options.onShown = {
            recorder.log.record(.selectorShown(at: ProcessInfo.processInfo.systemUptime))
            recorder.overlayVisibleWhenShown = !RegionSelector.panelWindowIDs.isEmpty
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                RegionSelector.cancel()
            }
        }
        let selection = await RegionSelector.selectRegions(options: options)
        guard case .single(.cancelled) = selection else {
            Issue.record("The selector didn't cancel")
            return
        }
        #expect(recorder.log.violation == nil)
        #expect(recorder.overlayVisibleWhenShown)
        #expect(RegionSelector.panelWindowIDs.isEmpty)
    }

    @Test func capturesTakenDuringSelectionNeverShowTheOverlay() async throws {
        let content = try await ScreenshotEngine.shareableContent()
        let before = await ScreenshotEngine.backdrops(for: content)
        let recorder = DuringCapture()
        var options = RegionSelector.Options(backdrops: before, freezeMode: .frozen)
        options.onShown = {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                let live = await ScreenshotEngine.shareableContent(listing: RegionSelector.panelWindowIDs) ?? content
                recorder.frames = await ScreenshotEngine.backdrops(for: live)
                RegionSelector.cancel()
            }
        }
        _ = await RegionSelector.selectRegions(options: options)
        #expect(!recorder.frames.isEmpty)
        for (displayID, image) in before {
            let first = try #require(PixelBuffer(image))
            let during = try #require(recorder.frames[displayID].flatMap(PixelBuffer.init))
            let different = first.differentPixels(from: during, channelTolerance: 40, searchRadius: 1) ?? first.width * first.height
            #expect(Double(different) < Double(first.width * first.height) * 0.05, "The selector showed up in a capture of display \(displayID)")
        }
    }
}

@MainActor
final class DuringCapture {
    var frames: [CGDirectDisplayID: CGImage] = [:]
}
