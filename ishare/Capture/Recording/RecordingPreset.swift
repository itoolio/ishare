import Defaults
import Foundation
import ishareCore
import KeyboardShortcuts
import Synchronization

enum RecordingDefaults {
    private static let overrides = Mutex<[String: any Sendable]>([:])
    private static let presetName = Mutex<String?>(nil)

    static subscript<Value: Defaults.Serializable & Sendable>(key: Defaults.Key<Value>) -> Value {
        if let value = overrides.withLock({ $0[key.name] }) as? Value {
            return value
        }
        return Defaults[key]
    }

    static var activePresetName: String? {
        presetName.withLock { $0 }
    }

    static func begin(_ preset: RecordingPreset?) {
        overrides.withLock { $0 = preset?.overrides ?? [:] }
        presetName.withLock { $0 = preset?.name }
        if let preset {
            Log.capture.info("Recording with the preset \(preset.name, privacy: .public)")
        }
    }

    static func end() {
        begin(nil)
    }
}

struct RecordingPreset: Codable, Hashable, Identifiable, Sendable, Defaults.Serializable {
    var id = UUID()
    var name: String
    var region = false
    var resolution = RecordingResolution.native
    var frameRate = RecordingFrameRate.fps60
    var useHEVC = false
    var useHDR = false
    var audioSource = RecordingAudioSource.allSystemAudio
    var audioBundleIDs: [String] = []
    var recordMic = false
    var showWebcam = false
    var webcamSize = WebcamBubbleSize.medium
    var webcamCorner = WebcamCorner.bottomRight
    var showKeystrokes = false
    var keystrokesShortcutsOnly = true
    var recordClicks = false
    var recordPointer = true
    var pointerSmoothing = false
    var pointerScale = 1.0
    var clickRipples = false
    var hidesIdlePointer = false
    var autoZoomEnabled = false
    var autoZoomLevel = 2.0
    var maxMinutes = 0
    var maxMegabytes = 0

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    static func fromCurrentSettings(name: String) -> RecordingPreset {
        var preset = RecordingPreset(name: name)
        preset.resolution = Defaults[.recordingResolution]
        preset.frameRate = Defaults[.recordingFrameRate]
        preset.useHEVC = Defaults[.useHEVC]
        preset.useHDR = Defaults[.useHDR]
        preset.audioSource = RecordingAudioSource.resolved(recordAudio: Defaults[.recordAudio], source: Defaults[.recordingAudioSource])
        preset.audioBundleIDs = Defaults[.recordingAudioBundleIDs]
        preset.recordMic = Defaults[.recordMic]
        preset.showWebcam = Defaults[.showWebcam]
        preset.webcamSize = Defaults[.webcamSize]
        preset.webcamCorner = Defaults[.webcamCorner]
        preset.showKeystrokes = Defaults[.showKeystrokes]
        preset.keystrokesShortcutsOnly = Defaults[.keystrokesShortcutsOnly]
        preset.recordClicks = Defaults[.recordClicks]
        preset.recordPointer = Defaults[.recordPointer]
        preset.pointerSmoothing = Defaults[.pointerSmoothing]
        preset.pointerScale = Defaults[.pointerScale]
        preset.clickRipples = Defaults[.clickRipples]
        preset.hidesIdlePointer = Defaults[.hidesIdlePointer]
        preset.autoZoomEnabled = Defaults[.autoZoomEnabled]
        preset.autoZoomLevel = Defaults[.autoZoomLevel]
        preset.maxMinutes = Defaults[.recordingMaxMinutes]
        preset.maxMegabytes = Defaults[.recordingMaxMegabytes]
        return preset
    }

    var overrides: [String: any Sendable] {
        var values: [String: any Sendable] = [:]
        func set<Value: Sendable>(_ key: Defaults.Key<Value>, _ value: Value) {
            values[key.name] = value
        }
        set(.recordingResolution, resolution)
        set(.recordingFrameRate, frameRate)
        set(.useHEVC, useHEVC)
        set(.useHDR, useHDR)
        set(.recordAudio, audioSource != .none)
        if audioSource != .none {
            set(.recordingAudioSource, audioSource)
        }
        set(.recordingAudioBundleIDs, audioBundleIDs)
        set(.recordMic, recordMic)
        set(.showWebcam, showWebcam)
        set(.webcamSize, webcamSize)
        set(.webcamCorner, webcamCorner)
        set(.showKeystrokes, showKeystrokes)
        set(.keystrokesShortcutsOnly, keystrokesShortcutsOnly)
        set(.recordClicks, recordClicks)
        set(.recordPointer, recordPointer)
        set(.pointerSmoothing, pointerSmoothing)
        set(.pointerScale, pointerScale)
        set(.clickRipples, clickRipples)
        set(.hidesIdlePointer, hidesIdlePointer)
        set(.autoZoomEnabled, autoZoomEnabled)
        set(.autoZoomLevel, autoZoomLevel)
        set(.recordingMaxMinutes, max(0, maxMinutes))
        set(.recordingMaxMegabytes, max(0, maxMegabytes))
        return values
    }

    var shortcutName: KeyboardShortcuts.Name {
        RecordingPresets.shortcutName(for: id)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, region, resolution, frameRate, useHEVC, useHDR, audioSource, audioBundleIDs, recordMic, showWebcam, webcamSize, webcamCorner
        case showKeystrokes, keystrokesShortcutsOnly, recordClicks, recordPointer, pointerSmoothing, pointerScale, clickRipples, hidesIdlePointer
        case autoZoomEnabled, autoZoomLevel, maxMinutes, maxMegabytes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = RecordingPreset(name: "")
        func value<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
            (try? container.decodeIfPresent(Value.self, forKey: key)) ?? fallback
        }
        func raw<Value: RawRepresentable>(_ key: CodingKeys, _ fallback: Value) -> Value where Value.RawValue: Decodable {
            value(key, Optional<Value.RawValue>.none).flatMap(Value.init(rawValue:)) ?? fallback
        }
        id = value(.id, UUID())
        name = value(.name, "")
        region = value(.region, fallback.region)
        resolution = raw(.resolution, fallback.resolution)
        frameRate = raw(.frameRate, fallback.frameRate)
        useHEVC = value(.useHEVC, fallback.useHEVC)
        useHDR = value(.useHDR, fallback.useHDR)
        audioSource = raw(.audioSource, fallback.audioSource)
        audioBundleIDs = value(.audioBundleIDs, fallback.audioBundleIDs)
        recordMic = value(.recordMic, fallback.recordMic)
        showWebcam = value(.showWebcam, fallback.showWebcam)
        webcamSize = raw(.webcamSize, fallback.webcamSize)
        webcamCorner = raw(.webcamCorner, fallback.webcamCorner)
        showKeystrokes = value(.showKeystrokes, fallback.showKeystrokes)
        keystrokesShortcutsOnly = value(.keystrokesShortcutsOnly, fallback.keystrokesShortcutsOnly)
        recordClicks = value(.recordClicks, fallback.recordClicks)
        recordPointer = value(.recordPointer, fallback.recordPointer)
        pointerSmoothing = value(.pointerSmoothing, fallback.pointerSmoothing)
        pointerScale = value(.pointerScale, fallback.pointerScale)
        clickRipples = value(.clickRipples, fallback.clickRipples)
        hidesIdlePointer = value(.hidesIdlePointer, fallback.hidesIdlePointer)
        autoZoomEnabled = value(.autoZoomEnabled, fallback.autoZoomEnabled)
        autoZoomLevel = value(.autoZoomLevel, fallback.autoZoomLevel)
        maxMinutes = value(.maxMinutes, fallback.maxMinutes)
        maxMegabytes = value(.maxMegabytes, fallback.maxMegabytes)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(region, forKey: .region)
        try container.encode(resolution.rawValue, forKey: .resolution)
        try container.encode(frameRate.rawValue, forKey: .frameRate)
        try container.encode(useHEVC, forKey: .useHEVC)
        try container.encode(useHDR, forKey: .useHDR)
        try container.encode(audioSource.rawValue, forKey: .audioSource)
        try container.encode(audioBundleIDs, forKey: .audioBundleIDs)
        try container.encode(recordMic, forKey: .recordMic)
        try container.encode(showWebcam, forKey: .showWebcam)
        try container.encode(webcamSize.rawValue, forKey: .webcamSize)
        try container.encode(webcamCorner.rawValue, forKey: .webcamCorner)
        try container.encode(showKeystrokes, forKey: .showKeystrokes)
        try container.encode(keystrokesShortcutsOnly, forKey: .keystrokesShortcutsOnly)
        try container.encode(recordClicks, forKey: .recordClicks)
        try container.encode(recordPointer, forKey: .recordPointer)
        try container.encode(pointerSmoothing, forKey: .pointerSmoothing)
        try container.encode(pointerScale, forKey: .pointerScale)
        try container.encode(clickRipples, forKey: .clickRipples)
        try container.encode(hidesIdlePointer, forKey: .hidesIdlePointer)
        try container.encode(autoZoomEnabled, forKey: .autoZoomEnabled)
        try container.encode(autoZoomLevel, forKey: .autoZoomLevel)
        try container.encode(maxMinutes, forKey: .maxMinutes)
        try container.encode(maxMegabytes, forKey: .maxMegabytes)
    }
}

@MainActor
enum RecordingPresets {
    static var all: [RecordingPreset] {
        Defaults[.recordingPresets]
    }

    static func preset(id: UUID) -> RecordingPreset? {
        all.first { $0.id == id }
    }

    static func preset(named query: String, in presets: [RecordingPreset] = all) -> RecordingPreset? {
        PresetNaming.index(matching: query, in: presets, id: \.id.uuidString, name: \.name).map { presets[$0] }
    }

    nonisolated static func shortcutName(for id: UUID) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("recordingPreset-\(id.uuidString)")
    }

    static func save(_ preset: RecordingPreset) {
        var presets = all
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        Defaults[.recordingPresets] = presets
    }

    static func uniqueName(_ name: String, excluding id: UUID? = nil) -> String {
        PresetNaming.uniqueName(name, among: all.filter { $0.id != id }.map(\.name), copySuffix: "copy".localized())
    }

    @discardableResult
    static func duplicate(_ preset: RecordingPreset) -> RecordingPreset {
        var copy = preset
        copy.id = UUID()
        copy.name = uniqueName(preset.name)
        var presets = all
        let index = presets.firstIndex { $0.id == preset.id }.map { $0 + 1 } ?? presets.endIndex
        presets.insert(copy, at: index)
        Defaults[.recordingPresets] = presets
        return copy
    }

    static func rename(_ preset: RecordingPreset, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var renamed = preset
        renamed.name = uniqueName(trimmed, excluding: preset.id)
        save(renamed)
    }

    static func delete(_ preset: RecordingPreset) {
        Defaults[.recordingPresets] = all.filter { $0.id != preset.id }
        KeyboardShortcuts.reset(preset.shortcutName)
    }

    static func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var presets = all
        presets.move(fromOffsets: source, toOffset: destination)
        Defaults[.recordingPresets] = presets
    }

    static func move(_ preset: RecordingPreset, by offset: Int) {
        guard let index = all.firstIndex(where: { $0.id == preset.id }) else { return }
        Defaults[.recordingPresets] = PresetNaming.moved(all, from: index, by: offset)
    }

    static func record(_ preset: RecordingPreset, gif: Bool = false, region: Bool? = nil) {
        CaptureSession.toggleRecording(gif: gif, region: region ?? preset.region, options: CaptureOptions(recordingPreset: preset))
    }

    static func record(presetID: UUID) {
        guard let preset = preset(id: presetID) else { return }
        record(preset)
    }
}

@MainActor
enum RecordingPresetShortcuts {
    private static var registered: Set<UUID> = []
    private static var observation: Task<Void, Never>?

    static func start() {
        sync(with: RecordingPresets.all)
        observation?.cancel()
        observation = Task { @MainActor in
            for await presets in Defaults.updates(.recordingPresets, initial: false) {
                sync(with: presets)
            }
        }
    }

    static func sync(with presets: [RecordingPreset]) {
        let ids = Set(presets.map(\.id))
        for removed in registered.subtracting(ids) {
            KeyboardShortcuts.removeHandler(for: RecordingPresets.shortcutName(for: removed))
        }
        for added in ids.subtracting(registered) {
            KeyboardShortcuts.onKeyUp(for: RecordingPresets.shortcutName(for: added)) {
                Task { @MainActor in
                    RecordingPresets.record(presetID: added)
                }
            }
        }
        registered = ids
    }
}
