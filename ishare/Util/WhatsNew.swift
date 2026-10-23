import AppKit
import Defaults
import SwiftUI

struct ReleaseNotes: Equatable, Sendable, Identifiable {
    struct Section: Equatable, Sendable, Identifiable {
        let title: String
        let items: [String]

        var id: String { title }
    }

    let version: String
    let sections: [Section]

    var id: String { version }
}

struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< count {
            let left = lhs.components[safe: index] ?? 0
            let right = rhs.components[safe: index] ?? 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    var majorMinor: String {
        "\(components[safe: 0] ?? 0).\(components[safe: 1] ?? 0)"
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }
}

enum ChangelogParser {
    static let userFacingSections = ["Features", "Bug Fixes"]

    static func parse(_ markdown: String) -> [ReleaseNotes] {
        var releases: [ReleaseNotes] = []
        var version: String?
        var sections: [ReleaseNotes.Section] = []
        var sectionTitle: String?
        var items: [String] = []

        func closeSection() {
            if let sectionTitle, userFacingSections.contains(sectionTitle), !items.isEmpty {
                sections.append(ReleaseNotes.Section(title: sectionTitle, items: items))
            }
            sectionTitle = nil
            items = []
        }

        func closeRelease() {
            closeSection()
            if let version, !sections.isEmpty {
                releases.append(ReleaseNotes(version: version, sections: sections))
            }
            version = nil
            sections = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") || (line.hasPrefix("## ") && !line.hasPrefix("### ")) {
                closeRelease()
                version = releaseVersion(in: line)
            } else if line.hasPrefix("### ") {
                closeSection()
                sectionTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if version != nil, sectionTitle != nil, line.hasPrefix("* ") || line.hasPrefix("- ") {
                let item = cleaned(String(line.dropFirst(2)))
                if !item.isEmpty {
                    items.append(item)
                }
            }
        }
        closeRelease()
        return releases
    }

    static func releaseVersion(in heading: String) -> String? {
        let text = heading.drop { $0 == "#" || $0 == " " }
        let candidate: Substring
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            candidate = text[text.index(after: text.startIndex) ..< close]
        } else {
            candidate = text.prefix { !$0.isWhitespace }
        }
        return AppVersion(String(candidate))?.description
    }

    static func cleaned(_ item: String) -> String {
        var text = item
        text = text.replacingOccurrences(of: #"\s*\(\[[0-9a-f]{6,40}\]\([^)]*\)\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*,?\s*closes\s+\[#\d+\]\([^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"^\*\*[^*]+:\*\*\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst()
    }
}

enum WhatsNew {
    static func releases(in all: [ReleaseNotes], after lastLaunched: String?, upTo current: String) -> [ReleaseNotes] {
        guard let currentVersion = AppVersion(current) else { return [] }
        let last = lastLaunched.flatMap(AppVersion.init)
        return all.filter { release in
            guard let version = AppVersion(release.version), version <= currentVersion else { return false }
            if let last { return version > last }
            return version.majorMinor == currentVersion.majorMinor
        }
    }

    static func shouldPresent(
        current: String, lastLaunched: String?, hasCompletedOnboarding: Bool, showsWhatsNew: Bool, isSuppressed: Bool
    ) -> Bool {
        guard !isSuppressed, hasCompletedOnboarding, showsWhatsNew, let currentVersion = AppVersion(current) else { return false }
        guard let lastLaunched else { return true }
        guard let last = AppVersion(lastLaunched) else { return true }
        return last < currentVersion
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func bundledReleases(in bundle: Bundle = .main) -> [ReleaseNotes] {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ChangelogParser.parse(text)
    }

    static var isSuppressed: Bool {
        ScreenshotMode.isActive || RuntimeEnvironment.isRunningTests
    }

    @MainActor static func presentIfNeeded() {
        guard !isSuppressed else { return }
        let current = currentVersion
        let lastLaunched = Defaults[.lastLaunchedVersion]
        Defaults[.lastLaunchedVersion] = current
        guard shouldPresent(
            current: current, lastLaunched: lastLaunched, hasCompletedOnboarding: Defaults[.hasCompletedOnboarding],
            showsWhatsNew: Defaults[.showsWhatsNew], isSuppressed: isSuppressed
        ) else { return }
        let notes = releases(in: bundledReleases(), after: lastLaunched, upTo: current)
        guard !notes.isEmpty else { return }
        WhatsNewWindow.show(releases: notes)
    }
}

@MainActor
enum WhatsNewWindow {
    private static var window: NSWindow?

    static func show() {
        let current = WhatsNew.currentVersion
        var notes = WhatsNew.releases(in: WhatsNew.bundledReleases(), after: nil, upTo: current)
        if notes.isEmpty {
            notes = Array(WhatsNew.bundledReleases().prefix(1))
        }
        show(releases: notes)
    }

    static func show(releases: [ReleaseNotes]) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let version = AppVersion(WhatsNew.currentVersion)?.majorMinor ?? WhatsNew.currentVersion
        let view = WhatsNewView(version: version, releases: releases) { close() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(format: "What’s New in ishare %@".localized(), version)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    static func close() {
        window?.close()
        window = nil
    }
}

struct WhatsNewView: View {
    let version: String
    let releases: [ReleaseNotes]
    let onClose: () -> Void
    @Default(.showsWhatsNew) private var showsWhatsNew

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(releases) { release in
                        releaseCard(release)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 500, height: 540)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatsNew.window")
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.menuAccent.gradient))
            Text(String(format: "What’s New in ishare %@".localized(), version))
                .font(.system(size: 21, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("whatsNew.title")
        }
        .frame(maxWidth: .infinity)
    }

    private func releaseCard(_ release: ReleaseNotes) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if releases.count > 1 {
                Text(String(format: "Version %@".localized(), release.version))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Label(section.title.localized(), systemImage: section.title == "Bug Fixes" ? "ladybug" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.menuAccent)
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Color.primary.opacity(0.35))
                                .frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                            Text(item)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var footer: some View {
        HStack {
            Toggle("Don’t show again".localized(), isOn: Binding(get: { !showsWhatsNew }, set: { showsWhatsNew = !$0 }))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("whatsNew.dontShowAgain")
            Spacer()
            Button("Continue".localized(), action: onClose)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .accessibilityIdentifier("whatsNew.continue")
        }
    }
}
