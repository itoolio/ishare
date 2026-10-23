import Combine
import SwiftUI

@MainActor
final class SettingsNavigator: ObservableObject {
    static var shared: SettingsNavigator { AppModel.shared.settings }

    struct AnchorRequest: Equatable {
        let anchor: String
        let token = UUID()
    }

    @Published var pane: SettingsPane?
    @Published var anchorRequest: AnchorRequest?
    @Published private(set) var highlightedAnchor: String?
    private var highlightTask: Task<Void, Never>?

    func reveal(_ anchor: String, in pane: SettingsPane? = nil) {
        if let pane {
            self.pane = pane
        }
        anchorRequest = AnchorRequest(anchor: anchor)
    }

    func highlight(_ anchor: String, duration: Duration = .seconds(1.6)) {
        highlightTask?.cancel()
        highlightedAnchor = anchor
        highlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            highlightedAnchor = nil
        }
    }
}

enum SettingsAnchor {
    static let language = "general.language"
    static let launchAtLogin = "general.launchAtLogin"
    static let aussieMode = "general.aussieMode"
    static let menuBarIcon = "general.menuBarIcon"
    static let menuLayout = "general.menuLayout"
    static let menuDensity = "general.menuDensity"
    static let appearance = "general.appearance"
    static let highContrast = "general.highContrast"
    static let clipboard = "general.clipboard"
    static let toastTimeout = "general.toastTimeout"
    static let toastPlacement = "general.toastPlacement"
    static let resultPresentation = "general.resultPresentation"
    static let sounds = "general.sounds"
    static let history = "general.history"
    static let clearHistory = "general.clearHistory"
}

struct SettingsSearchEntry: Equatable, Sendable {
    let pane: SettingsPane
    let title: String
    let keywords: [String]
    let anchor: String?

    init(_ title: String, pane: SettingsPane, keywords: [String] = [], anchor: String? = nil) {
        self.pane = pane
        self.title = title
        self.keywords = keywords
        self.anchor = anchor
    }

    var searchTerms: [String] {
        [title] + keywords
    }
}

@MainActor
protocol SettingsSearchable {
    static var searchEntries: [SettingsSearchEntry] { get }
}

extension SettingsPane {
    @MainActor var searchable: any SettingsSearchable.Type {
        switch self {
        case .general: GeneralSettingsView.self
        case .capture: CaptureSettingsView.self
        case .recording: RecordingSettingsView.self
        case .uploaders: UploaderSettingsView.self
        case .keybinds: KeybindSettingsView.self
        case .advanced: AdvancedSettingsView.self
        }
    }
}

struct SettingsSearchMatch: Equatable, Sendable {
    let pane: SettingsPane
    let keyword: String?
    let anchor: String?

    init(pane: SettingsPane, keyword: String?, anchor: String? = nil) {
        self.pane = pane
        self.keyword = keyword
        self.anchor = anchor
    }
}

@MainActor
enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = SettingsPane.allCases.flatMap { $0.searchable.searchEntries }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":…")))
    }

    static func matches(
        for query: String,
        entries: [SettingsSearchEntry] = entries,
        localize: (String) -> String = { $0.localized() }
    ) -> [SettingsSearchMatch] {
        let needle = normalized(query)
        guard !needle.isEmpty else {
            return SettingsPane.allCases.map { SettingsSearchMatch(pane: $0, keyword: nil) }
        }
        return SettingsPane.allCases.compactMap { pane in
            if contains(pane.title, needle, localize: localize) {
                return SettingsSearchMatch(pane: pane, keyword: nil)
            }
            for entry in entries where entry.pane == pane {
                if let keyword = entry.searchTerms.first(where: { contains($0, needle, localize: localize) }) {
                    return SettingsSearchMatch(pane: pane, keyword: keyword, anchor: entry.anchor)
                }
            }
            return nil
        }
    }

    private static func contains(_ candidate: String, _ needle: String, localize: (String) -> String) -> Bool {
        normalized(candidate).contains(needle) || normalized(localize(candidate)).contains(needle)
    }
}

struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Settings".localized(), text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("settings.search")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .helpAndAccessibilityLabel("Clear".localized())
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}
