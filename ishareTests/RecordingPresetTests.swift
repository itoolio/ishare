import Defaults
import Foundation
import Testing
@testable import ishare

@MainActor
@Suite(.serialized)
struct RecordingPresetTests {
    private func command(_ string: String) -> URLSchemeCommand? {
        guard let url = URL(string: string), case let .success(request) = URLSchemeParser.parse(url) else { return nil }
        return request.command
    }

    @Test func roundTripsThroughJSON() throws {
        var preset = RecordingPreset(name: "Tutorial")
        preset.resolution = .p1080
        preset.frameRate = .fps30
        preset.audioSource = .selectedApps
        preset.audioBundleIDs = ["com.apple.Safari"]
        preset.webcamCorner = .topLeft
        preset.pointerScale = 1.5
        preset.maxMinutes = 5
        preset.region = true
        let data = try JSONEncoder().encode(preset)
        #expect(try JSONDecoder().decode(RecordingPreset.self, from: data) == preset)
    }

    @Test func decodesOlderOrPartialPresets() throws {
        let json = Data(#"{"id":"6E1C1E4D-5B51-4C66-9E0F-6A6E0A1D0B11","name":"Old","resolution":"bogus","frameRate":30}"#.utf8)
        let preset = try JSONDecoder().decode(RecordingPreset.self, from: json)
        #expect(preset.name == "Old")
        #expect(preset.resolution == .native)
        #expect(preset.frameRate == .fps30)
        #expect(preset.recordPointer)
    }

    @Test func overridesApplyOnlyWhileThePresetIsActive() {
        var preset = RecordingPreset(name: "Demo")
        preset.resolution = .p720
        preset.maxMinutes = 3
        preset.audioSource = .none
        let before = Defaults[.recordingResolution]
        RecordingDefaults.begin(preset)
        #expect(RecordingDefaults[.recordingResolution] == .p720)
        #expect(RecordingDefaults[.recordingMaxMinutes] == 3)
        #expect(RecordingDefaults[.recordAudio] == false)
        #expect(RecordingAudioSource.current == .none)
        #expect(RecordingDefaults.activePresetName == "Demo")
        #expect(Defaults[.recordingResolution] == before)
        RecordingDefaults.end()
        #expect(RecordingDefaults[.recordingResolution] == before)
        #expect(RecordingDefaults.activePresetName == nil)
    }

    @Test func findsPresetsByName() {
        let presets = [RecordingPreset(name: "Bug Report"), RecordingPreset(name: "Demo 4K")]
        #expect(RecordingPresets.preset(named: "bug report", in: presets)?.name == "Bug Report")
        #expect(RecordingPresets.preset(named: presets[1].id.uuidString, in: presets)?.name == "Demo 4K")
        #expect(RecordingPresets.preset(named: "nothing", in: presets) == nil)
    }

    @Test func parsesThePresetParameter() throws {
        #expect(command("ishare://record/start?preset=Demo%204K") == .record(.start, gif: false, region: false, preset: "Demo 4K"))
        #expect(command("ishare://record/start?preset=") == .record(.start, gif: false, region: false))
        guard case let .run(invocation) = try CLIArguments.parse(["record", "start", "--preset", "Demo"]) else {
            Issue.record("Expected a runnable command")
            return
        }
        #expect(invocation.command == .record(.start, preset: "Demo"))
        #expect(throws: CLIArgumentError.unknownOption("--preset")) {
            try CLIArguments.parse(["history", "--preset", "Demo"])
        }
    }

    @Test func reportsAnUnknownPresetOverAutomation() async {
        let result = await LiveAutomationActions.shared.record(.start, gif: false, region: false, preset: "ishare-test-missing-preset-\(UUID().uuidString)")
        guard case .failure = result else {
            Issue.record("An unknown preset must fail")
            return
        }
    }
}
