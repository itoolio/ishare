import Defaults
import Foundation
import KeyboardShortcuts

struct UploadPreset: Codable, Hashable, Identifiable, Sendable, Defaults.Serializable {
    var id: UUID
    var name: String
    var destination: UploadDestination
    var additionalDestinations: [UploadDestination]
    var shortener: URLShortenerConfiguration?
    var stepOverrides: [String: Bool]

    init(
        id: UUID = UUID(), name: String, destination: UploadDestination, additionalDestinations: [UploadDestination] = [],
        shortener: URLShortenerConfiguration? = nil, stepOverrides: [AfterCaptureStep: Bool] = [:]
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.additionalDestinations = additionalDestinations
        self.shortener = shortener
        self.stepOverrides = Dictionary(uniqueKeysWithValues: stepOverrides.map { ($0.key.rawValue, $0.value) })
    }

    enum CodingKeys: String, CodingKey {
        case id, name, destination, additionalDestinations, shortener, stepOverrides
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        destination = try container.decodeIfPresent(UploadDestination.self, forKey: .destination) ?? .builtIn(.IMGUR)
        additionalDestinations = try container.decodeIfPresent([UploadDestination].self, forKey: .additionalDestinations) ?? []
        shortener = try container.decodeIfPresent(URLShortenerConfiguration.self, forKey: .shortener)
        stepOverrides = try container.decodeIfPresent([String: Bool].self, forKey: .stepOverrides) ?? [:]
    }

    func override(for step: AfterCaptureStep) -> Bool? {
        stepOverrides[step.rawValue]
    }

    mutating func setOverride(_ value: Bool?, for step: AfterCaptureStep) {
        stepOverrides[step.rawValue] = value
    }

    var shortcutName: KeyboardShortcuts.Name {
        UploadPresets.shortcutName(for: id)
    }
}

extension CaptureOptions {
    @MainActor func isEnabled(_ step: AfterCaptureStep) -> Bool {
        let value = preset?.override(for: step) ?? defaultValue(for: step)
        guard let dependency = step.dependsOn else { return value }
        return value && isEnabled(dependency)
    }

    @MainActor private func defaultValue(for step: AfterCaptureStep) -> Bool {
        preset != nil && step == .upload ? true : step.isEnabled
    }
}

@MainActor
enum UploadPresets {
    static var all: [UploadPreset] {
        Defaults[.uploadPresets]
    }

    static func preset(id: UUID) -> UploadPreset? {
        all.first { $0.id == id }
    }

    nonisolated static func shortcutName(for id: UUID) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("preset-\(id.uuidString)")
    }

    static func save(_ preset: UploadPreset) {
        var presets = all
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        Defaults[.uploadPresets] = presets
    }

    static func delete(_ preset: UploadPreset) {
        Defaults[.uploadPresets] = all.filter { $0.id != preset.id }
        KeyboardShortcuts.reset(preset.shortcutName)
    }

    static func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var presets = all
        presets.move(fromOffsets: source, toOffset: destination)
        Defaults[.uploadPresets] = presets
    }

    static func capture(_ preset: UploadPreset, type: CaptureType = .REGION) async {
        await CaptureSession.captureImage(type, options: CaptureOptions(preset: preset))
    }

    static func capture(presetID: UUID, type: CaptureType = .REGION) async {
        guard let preset = preset(id: presetID) else { return }
        await capture(preset, type: type)
    }
}

@MainActor
enum UploadPresetShortcuts {
    private static var registered: Set<UUID> = []
    private static var observation: Task<Void, Never>?

    static func start() {
        sync(with: UploadPresets.all)
        observation?.cancel()
        observation = Task { @MainActor in
            for await presets in Defaults.updates(.uploadPresets, initial: false) {
                sync(with: presets)
            }
        }
    }

    static func sync(with presets: [UploadPreset]) {
        let ids = Set(presets.map(\.id))
        for removed in registered.subtracting(ids) {
            KeyboardShortcuts.removeHandler(for: UploadPresets.shortcutName(for: removed))
        }
        for added in ids.subtracting(registered) {
            KeyboardShortcuts.onKeyUp(for: UploadPresets.shortcutName(for: added)) {
                Task { @MainActor in
                    await UploadPresets.capture(presetID: added)
                }
            }
        }
        registered = ids
    }
}
