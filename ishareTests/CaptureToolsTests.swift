import AppKit
import CoreImage.CIFilterBuiltins
import Defaults
import Foundation
import Testing
@testable import ishare

enum TextImages {
    static func render(_ lines: [(String, CGPoint)], size: CGSize = CGSize(width: 900, height: 300), fontSize: CGFloat = 36) -> CGImage {
        TestImages.make(width: Int(size.width), height: Int(size.height)) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
            for (text, topLeft) in lines {
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: CGPoint(x: topLeft.x, y: size.height - topLeft.y - string.size().height))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func qrCode(_ payload: String) -> CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let padded = output.transformed(by: CGAffineTransform(translationX: 40, y: 40))
            .composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -40, dy: -40).offsetBy(dx: 40, dy: 40)))
        return ImageProcessing.render(padded)!
    }
}

struct TextLayoutTests {
    func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.2, height: CGFloat = 0.05) -> RecognizedLine {
        RecognizedLine(text: text, boundingBox: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func ordersLinesTopToBottomThenLeftToRight() {
        let lines = [
            line("bottom", x: 0.1, y: 0.1),
            line("right", x: 0.6, y: 0.8),
            line("left", x: 0.1, y: 0.81),
            line("middle", x: 0.3, y: 0.5),
        ]
        #expect(TextLayout.ordered(lines).map(\.text) == ["left", "right", "middle", "bottom"])
        #expect(TextLayout.joined(lines) == "left right\nmiddle\nbottom")
    }

    @Test func keepsSlightlyOffsetLinesOnSeparateRowsWhenTheyDoNotOverlap() {
        let lines = [line("first", x: 0.5, y: 0.7), line("second", x: 0.1, y: 0.6)]
        #expect(TextLayout.joined(lines) == "first\nsecond")
    }

    @Test func findsWordRanges() {
        let ranges = TextLayout.wordRanges(in: "mail  me@x.io now")
        #expect(ranges == [NSRange(location: 0, length: 4), NSRange(location: 6, length: 7), NSRange(location: 14, length: 3)])
    }

    @Test func summarizesRecognizedTextForTheBezel() {
        #expect(TextCapturePreview.summary(of: "Hello\n  world") == "Hello world")
        let long = String(repeating: "abcde ", count: 20)
        let summary = TextCapturePreview.summary(of: long, limit: 12)
        #expect(summary == "abcde abcde…")
    }

    @Test func textIsReachableAsACaptureType() {
        #expect(CaptureType(rawValue: "text".uppercased()) == .TEXT)
    }

    @Test func recognizesRenderedTextInReadingOrder() async throws {
        let image = TextImages.render([
            ("Second column", CGPoint(x: 480, y: 30)),
            ("First column", CGPoint(x: 30, y: 30)),
            ("Next line here", CGPoint(x: 30, y: 160)),
        ])
        let text = try await TextRecognition.recognize(in: image)
        let rows = text.components(separatedBy: "\n")
        #expect(rows.count == 2)
        #expect(rows.first?.hasPrefix("First column") == true)
        #expect(rows.first?.hasSuffix("Second column") == true)
        #expect(rows.last == "Next line here")
    }
}

struct CodeDetectionTests {
    @Test func prefersWebLinksOverOtherPayloads() {
        #expect(CodeDetection.preferredPayload(["WIFI:S:home;;", "https://example.com/a"]) == "https://example.com/a")
        #expect(CodeDetection.preferredPayload(["WIFI:S:home;;", "tel:123"]) == "WIFI:S:home;;")
        #expect(CodeDetection.preferredPayload([]) == nil)
    }

    @Test func recognizesOnlyHTTPLinksAsWebLinks() {
        #expect(CodeDetection.isWebLink("https://ishare.dev"))
        #expect(CodeDetection.isWebLink("http://example.com/path?x=1"))
        #expect(!CodeDetection.isWebLink("mailto:a@b.c"))
        #expect(!CodeDetection.isWebLink("https://"))
        #expect(!CodeDetection.isWebLink("hello world"))
    }

    @Test func removesDuplicateAndEmptyPayloads() {
        #expect(CodeDetection.uniquePayloads([" a ", "a", "", "b"]) == ["a", "b"])
    }

    @Test func detectsAQRCodePayload() async throws {
        let payloads = try await CodeDetection.payloads(in: TextImages.qrCode("https://example.com/qr"))
        #expect(payloads == ["https://example.com/qr"])
    }
}

struct SensitiveTextMatcherTests {
    func matched(_ text: String, _ category: RedactionCategory) -> [String] {
        SensitiveTextMatcher.matches(in: text, categories: [category]).map { SensitiveTextMatcher.substring(text, $0) }
    }

    @Test func validatesCardNumbersWithLuhn() {
        #expect(Luhn.isValid("4111 1111 1111 1111"))
        #expect(Luhn.isValid("5500-0000-0000-0004"))
        #expect(Luhn.isValid("378282246310005"))
        #expect(!Luhn.isValid("4111 1111 1111 1112"))
        #expect(!Luhn.isValid("1234"))
        #expect(!Luhn.isValid("4111a1111b1111c1111"))
    }

    @Test func findsCreditCardNumbers() {
        #expect(matched("Card: 4111 1111 1111 1111 exp 12/29", .creditCards) == ["4111 1111 1111 1111"])
        #expect(matched("Order 4111 1111 1111 1112", .creditCards).isEmpty)
    }

    @Test func findsEmailAddresses() {
        #expect(matched("Contact jane.doe+work@mail.example.co.uk today", .emailAddresses) == ["jane.doe+work@mail.example.co.uk"])
        #expect(matched("no at sign here", .emailAddresses).isEmpty)
    }

    @Test func findsKnownTokenFormats() {
        let samples = [
            "ghp_" + String(repeating: "a1B2", count: 9),
            "AKIA" + "ABCDEFGHIJKLMNOP",
            "sk-ant-" + String(repeating: "x9Y", count: 10),
            "xoxb-1234567890-abcdefghij",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
        ]
        for sample in samples {
            #expect(matched("value \(sample) end", .apiKeys) == [sample])
        }
    }

    @Test func findsAssignedSecretsAndLongMixedTokens() {
        #expect(matched("api_key = abcdef1234567890xyz", .apiKeys) == ["abcdef1234567890xyz"])
        #expect(matched("token: Zm9vYmFyYmF6cXV4", .apiKeys) == ["Zm9vYmFyYmF6cXV4"])
        let generic = "Ab3" + String(repeating: "x7Q", count: 11)
        #expect(matched("id \(generic)", .apiKeys) == [generic])
        #expect(matched("commit 3f9a2c4e5b6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f", .apiKeys).isEmpty)
        #expect(matched("the quick brown fox", .apiKeys).isEmpty)
    }

    @Test func findsIPAddresses() {
        #expect(matched("server 192.168.1.20 and 10.0.0.1", .ipAddresses) == ["192.168.1.20", "10.0.0.1"])
        #expect(matched("version 1.2.3.4.5 and 300.1.1.1", .ipAddresses).isEmpty)
        #expect(matched("v6 fe80::1ff:fe23:4567:890a ok", .ipAddresses) == ["fe80::1ff:fe23:4567:890a"])
        #expect(matched("at 12:30:45 and std::string", .ipAddresses).isEmpty)
    }

    @Test func findsPhoneNumbers() {
        #expect(matched("Call +1 (415) 555-0132 now", .phoneNumbers).first?.contains("555-0132") == true)
        #expect(matched("Room 42", .phoneNumbers).isEmpty)
    }

    @Test func mergesOverlappingMatchesAcrossCategories() {
        let ranges = SensitiveTextMatcher.merged([NSRange(location: 5, length: 5), NSRange(location: 0, length: 6), NSRange(location: 20, length: 2)])
        #expect(ranges == [NSRange(location: 0, length: 10), NSRange(location: 20, length: 2)])
    }
}

struct RedactionGeometryTests {
    @Test func mapsNormalizedVisionBoxesToTopLeftPixels() {
        let rect = RedactionGeometry.imageRect(forNormalized: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), imageSize: CGSize(width: 400, height: 200))
        #expect(rect == CGRect(x: 100, y: 50, width: 200, height: 50))
    }

    @Test func usesTheBoxesOfTheWordsAMatchTouches() {
        let line = RecognizedLine(
            text: "mail me@x.io now",
            boundingBox: CGRect(x: 0, y: 0.5, width: 1, height: 0.1),
            words: [
                RecognizedWord(range: NSRange(location: 0, length: 4), boundingBox: CGRect(x: 0, y: 0.5, width: 0.2, height: 0.1)),
                RecognizedWord(range: NSRange(location: 5, length: 7), boundingBox: CGRect(x: 0.3, y: 0.5, width: 0.4, height: 0.1)),
                RecognizedWord(range: NSRange(location: 13, length: 3), boundingBox: CGRect(x: 0.8, y: 0.5, width: 0.2, height: 0.1)),
            ]
        )
        #expect(RedactionGeometry.normalizedBox(for: NSRange(location: 5, length: 7), in: line) == CGRect(x: 0.3, y: 0.5, width: 0.4, height: 0.1))
    }

    @Test func fallsBackToAProportionalSliceOfTheLine() {
        let line = RecognizedLine(text: "abcdefghij", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1))
        let box = RedactionGeometry.normalizedBox(for: NSRange(location: 2, length: 4), in: line)
        #expect(abs(box.minX - 0.2) < 0.0001)
        #expect(abs(box.width - 0.2) < 0.0001)
        #expect(box.minY == 0.2)
    }

    @Test func padsAndClampsRectsToTheImage() {
        let line = RecognizedLine(text: "a@b.io", boundingBox: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.1))
        let rects = RedactionGeometry.rects(for: [line], categories: [.emailAddresses], imageSize: CGSize(width: 200, height: 100))
        #expect(rects == [CGRect(x: 0, y: 0, width: 102, height: 12)])
        #expect(RedactionGeometry.rects(for: [line], categories: [.phoneNumbers], imageSize: CGSize(width: 200, height: 100)).isEmpty)
    }

    @Test func redactsARenderedEmailAndSkipsCleanImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "redaction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sensitive = directory.appending(path: "sensitive.png")
        try ImageEncoder.write(TextImages.render([("Write to jane.doe@example.com", CGPoint(x: 30, y: 60))]), as: .PNG, to: sensitive)
        let clean = directory.appending(path: "clean.png")
        try ImageEncoder.write(TextImages.render([("Nothing secret here", CGPoint(x: 30, y: 60))]), as: .PNG, to: clean)

        let redacted = try #require(try await Redactor.redactedCopy(of: sensitive, categories: [.emailAddresses]))
        defer { Redactor.discard(redacted) }
        #expect(redacted.lastPathComponent == "sensitive.png")
        #expect(redacted != sensitive)
        let recognized = try await TextRecognition.recognize(in: #require(ImageEncoder.loadImage(at: redacted)))
        #expect(!recognized.contains("jane.doe@example.com"))
        #expect(try await Redactor.redactedCopy(of: clean, categories: [.emailAddresses]) == nil)
        #expect(try await Redactor.redactedCopy(of: sensitive, categories: []) == nil)
    }
}

struct CaptureDelayTests {
    @Test func appliesTheSettingToScreenAndWindowCapturesOnly() {
        #expect(CaptureDelay.effectiveSeconds(for: .SCREEN, explicit: nil, setting: .five) == 5)
        #expect(CaptureDelay.effectiveSeconds(for: .WINDOW, explicit: nil, setting: .three) == 3)
        #expect(CaptureDelay.effectiveSeconds(for: .REGION, explicit: nil, setting: .ten) == 0)
        #expect(CaptureDelay.effectiveSeconds(for: .SCREEN, explicit: nil, setting: .off) == 0)
    }

    @Test func prefersAnExplicitDelay() {
        #expect(CaptureDelay.effectiveSeconds(for: .REGION, explicit: 4, setting: .off) == 4)
        #expect(CaptureDelay.effectiveSeconds(for: .SCREEN, explicit: 0, setting: .ten) == 0)
        #expect(CaptureDelay.effectiveSeconds(for: .WINDOW, explicit: -3, setting: .ten) == 0)
    }

    @Test func placesTheCountdownNextToThePointerWithinTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 200, height: 50)
        #expect(CaptureCountdown.origin(for: size, pointer: CGPoint(x: 100, y: 400), visibleFrame: visible) == CGPoint(x: 118, y: 332))
        #expect(CaptureCountdown.origin(for: size, pointer: CGPoint(x: 990, y: 400), visibleFrame: visible) == CGPoint(x: 772, y: 332))
        #expect(CaptureCountdown.origin(for: size, pointer: CGPoint(x: 100, y: 20), visibleFrame: visible) == CGPoint(x: 118, y: 38))
    }
}

struct IntervalPlanTests {
    @Test func countsPlannedFrames() {
        #expect(IntervalPlan(interval: 2, stopMode: .frameCount, frameCount: 12, duration: 0).plannedFrames == 12)
        #expect(IntervalPlan(interval: 2, stopMode: .frameCount, frameCount: 0, duration: 0).plannedFrames == 2)
        #expect(IntervalPlan(interval: 2, stopMode: .frameCount, frameCount: 9999, duration: 0).plannedFrames == 500)
        #expect(IntervalPlan(interval: 5, stopMode: .duration, frameCount: 0, duration: 60).plannedFrames == 13)
        #expect(IntervalPlan(interval: 30, stopMode: .duration, frameCount: 0, duration: 10).plannedFrames == 1)
    }

    @Test func schedulesFramesAtFixedOffsets() {
        let plan = IntervalPlan(interval: 5, stopMode: .frameCount, frameCount: 3, duration: 0)
        #expect(plan.offset(ofFrame: 0) == .zero)
        #expect(plan.offset(ofFrame: 2) == .seconds(10))
    }

    @Test func namesTheFolderAndFrames() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(IntervalPlan.folderName(prefix: "Shots", date: date) == "shots-interval-1700000000")
        #expect(IntervalPlan.folderName(prefix: " ", date: date) == "ishare-interval-1700000000")
        #expect(IntervalPlan.frameName(index: 0, ext: "PNG") == "frame-0001.png")
        #expect(IntervalPlan.frameName(index: 41, ext: "jpg") == "frame-0042.jpg")
    }

    @Test func combinesFramesIntoAGIF() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "interval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frames = try [CaptureColor(red: 1, green: 0, blue: 0), CaptureColor(red: 0, green: 0, blue: 1)].enumerated().map { index, color in
            let url = directory.appending(path: IntervalPlan.frameName(index: index, ext: "png"))
            try ImageEncoder.write(TestImages.solid(width: 40, height: 30, color: color), as: .PNG, to: url)
            return url
        }
        let gif = directory.appending(path: "out.gif")
        try IntervalGIF.write(frames: frames, to: gif)
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(CGImageSourceGetType(source) as String? == "com.compuserve.gif")
    }
}

struct CaptureProfileTests {
    let global = CaptureSettings(addsBackground: false, blursPrivateApps: true, includesWindowShadow: true, fileNamePrefix: "ishare")

    @Test func matchesProfilesByBundleIdentifierIgnoringCase() {
        let profiles = [
            CaptureProfile(bundleIdentifier: "com.apple.Safari", appName: "Safari", isEnabled: false),
            CaptureProfile(bundleIdentifier: "com.apple.safari", appName: "Safari", addsBackground: true),
        ]
        #expect(CaptureProfileMatcher.profile(for: "COM.APPLE.SAFARI", in: profiles)?.addsBackground == true)
        #expect(CaptureProfileMatcher.profile(for: "com.apple.mail", in: profiles) == nil)
        #expect(CaptureProfileMatcher.profile(for: nil, in: profiles) == nil)
        #expect(CaptureProfileMatcher.profile(for: "", in: profiles) == nil)
    }

    @Test func overridesOnlyTheFieldsAProfileSets() {
        let profile = CaptureProfile(
            bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", blursPrivateApps: false, includesWindowShadow: false, fileNamePrefix: " slack ")
        let resolved = CaptureProfileMatcher.settings(for: "com.tinyspeck.slackmacgap", global: global, profiles: [profile])
        #expect(resolved == CaptureSettings(addsBackground: false, blursPrivateApps: false, includesWindowShadow: false, fileNamePrefix: "slack"))
    }

    @Test func ignoresDisabledProfilesAndBlankPrefixes() {
        var profile = CaptureProfile(bundleIdentifier: "a.b", appName: "A", addsBackground: true, fileNamePrefix: "   ")
        #expect(global.applying(profile) == CaptureSettings(addsBackground: true, blursPrivateApps: true, includesWindowShadow: true, fileNamePrefix: "ishare"))
        profile.isEnabled = false
        #expect(global.applying(profile) == global)
        #expect(global.applying(nil) == global)
    }

    @Test func roundTripsThroughCodable() throws {
        let profile = CaptureProfile(bundleIdentifier: "a.b", appName: "A", addsBackground: false, fileNamePrefix: "x")
        let decoded = try JSONDecoder().decode(CaptureProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }

    @Test func mapsTriStateOverrides() {
        #expect(ProfileOverride(nil) == .inherit)
        #expect(ProfileOverride(true).value == true)
        #expect(ProfileOverride(false).value == false)
        #expect(ProfileOverride.inherit.value == nil)
    }
}

struct WindowTitleNameTests {
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func namesFilesAfterTheWindowTitle() {
        let name = WindowTitleName.fileName(title: "Pull Request #42: Fix/Refactor", appName: "Safari", fallbackPrefix: "ishare", fallbackSuffix: "Safari", ext: "PNG", date: date)
        #expect(name == "pull-request-#42-fix-refactor-1700000000.png")
    }

    @Test func stripsTheBrowserNameFromTabTitles() {
        #expect(WindowTitleName.component(fromTitle: "Inbox (3) - Google Chrome", appName: "Google Chrome") == "inbox-(3)")
        #expect(WindowTitleName.component(fromTitle: "Docs — Mozilla Firefox", appName: "Mozilla Firefox") == "docs")
        #expect(WindowTitleName.component(fromTitle: "Google Chrome", appName: "Google Chrome") == "google-chrome")
    }

    @Test func truncatesLongTitlesToSixtyCharacters() {
        let component = WindowTitleName.component(fromTitle: String(repeating: "word ", count: 30), appName: nil)
        #expect(component.map(\.count).map { $0 <= 60 } == true)
        #expect(component?.hasSuffix("-") == false)
        #expect(component?.hasPrefix("word-word") == true)
    }

    @Test func fallsBackToTheRegularNameWithoutAUsableTitle() {
        let fallback = CaptureFileName.make(prefix: "ishare", suffix: "Finder", ext: "png", date: date)
        #expect(WindowTitleName.fileName(title: nil, appName: "Finder", fallbackPrefix: "ishare", fallbackSuffix: "Finder", ext: "png", date: date) == fallback)
        #expect(WindowTitleName.fileName(title: " :/: ", appName: nil, fallbackPrefix: "ishare", fallbackSuffix: "Finder", ext: "png", date: date) == fallback)
    }

    @MainActor
    @Test func savesWithTheTitleOnlyWhenEnabled() {
        let saved = Defaults[.nameFilesAfterWindowTitle]
        defer { Defaults[.nameFilesAfterWindowTitle] = saved }
        let captured = CapturedImage(
            image: TestImages.solid(width: 2, height: 2, color: CaptureColor(red: 0, green: 0, blue: 0)),
            suffix: "Notes", source: CaptureSource(bundleIdentifier: "com.apple.Notes", appName: "Notes", windowTitle: "Groceries")
        )
        Defaults[.nameFilesAfterWindowTitle] = false
        #expect(ImageCaptureFlow.fileName(for: captured, ext: "png").hasSuffix("-notes.png"))
        Defaults[.nameFilesAfterWindowTitle] = true
        #expect(ImageCaptureFlow.fileName(for: captured, ext: "png").hasPrefix("groceries-"))
    }
}
