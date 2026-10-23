import CryptoKit
import Foundation

enum DiagnosticKind: String, CaseIterable, Sendable {
    case crash
    case hang
    case cpuException
    case diskWriteException

    var title: String {
        switch self {
        case .crash: "Crash".localized()
        case .hang: "Hang".localized()
        case .cpuException: "CPU Exception".localized()
        case .diskWriteException: "Disk Write Exception".localized()
        }
    }

    var issueTitle: String {
        switch self {
        case .crash: "crash"
        case .hang: "hang"
        case .cpuException: "CPU exception"
        case .diskWriteException: "disk write exception"
        }
    }
}

struct DiagnosticReport: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: DiagnosticKind
    let date: Date
    let summary: String
    let appVersion: String
    let osVersion: String

    var id: URL { url }
}

struct DiagnosticsStore: Sendable {
    static let defaultLimit = 20
    static let changedNotification = Notification.Name("dev.adrian.ishare.diagnosticsChanged")
    static let shared = DiagnosticsStore(directory: defaultDirectory)

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "ishare/Diagnostics", directoryHint: .isDirectory)
    }

    let directory: URL
    var limit: Int = defaultLimit

    @discardableResult
    func save(kind: DiagnosticKind, date: Date, summary: String, appVersion: String, osVersion: String, diagnostic: Data) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: diagnostic).prefix(6).map { String(format: "%02x", $0) }.joined()
        let url = directory.appending(path: "\(Int64(date.timeIntervalSince1970 * 1000))-\(kind.rawValue)-\(digest).json")
        if !FileManager.default.fileExists(atPath: url.path) {
            let diagnosticObject = (try? JSONSerialization.jsonObject(with: diagnostic)) ?? String(decoding: diagnostic, as: UTF8.self)
            let envelope: [String: Any] = [
                "kind": kind.rawValue,
                "date": ISO8601DateFormatter().string(from: date),
                "summary": summary,
                "appVersion": appVersion,
                "osVersion": osVersion,
                "diagnostic": diagnosticObject,
            ]
            let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        }
        prune()
        return url
    }

    func reports() -> [DiagnosticReport] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(Self.report(at:))
            .sorted { ($0.date, $0.url.lastPathComponent) > ($1.date, $1.url.lastPathComponent) }
    }

    static func report(at url: URL) -> DiagnosticReport? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = (envelope["kind"] as? String).flatMap(DiagnosticKind.init(rawValue:)),
              let date = (envelope["date"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) })
        else { return nil }
        return DiagnosticReport(
            url: url, kind: kind, date: date, summary: envelope["summary"] as? String ?? "",
            appVersion: envelope["appVersion"] as? String ?? "", osVersion: envelope["osVersion"] as? String ?? ""
        )
    }

    func contents(of report: DiagnosticReport) -> String? {
        try? String(contentsOf: report.url, encoding: .utf8)
    }

    func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let reports = reports()
        let kept = Set(reports.prefix(limit).map(\.url.lastPathComponent))
        for file in files where file.pathExtension == "json" && !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func deleteAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

enum DiagnosticsIssue {
    static let newIssueURL = "https://github.com/itoolio/ishare/issues/new"
    static let maximumURLLength = 7000

    static func url(reports: [DiagnosticReport], appVersion: String, osVersion: String, maximumLength: Int = maximumURLLength) -> URL {
        let title = reports.first.map { "Diagnostics: \($0.kind.issueTitle) in ishare \(appVersion)" } ?? "Bug report for ishare \(appVersion)"
        var included = reports
        while true {
            let url = make(title: title, body: body(reports: included, total: reports.count, appVersion: appVersion, osVersion: osVersion))
            if url.absoluteString.count <= maximumLength || included.isEmpty {
                return url
            }
            included.removeLast()
        }
    }

    static func body(reports: [DiagnosticReport], total: Int, appVersion: String, osVersion: String) -> String {
        var lines = [
            "### What happened?", "", "", "",
            "### Environment", "",
            "- ishare: \(appVersion)",
            "- macOS: \(osVersion)",
            "",
            "### Diagnostics", "",
        ]
        if reports.isEmpty {
            lines.append("No crash or hang reports were collected.")
        }
        let formatter = ISO8601DateFormatter()
        for report in reports {
            var line = "- \(formatter.string(from: report.date)) \(report.kind.issueTitle)"
            if !report.appVersion.isEmpty { line += " in \(report.appVersion)" }
            if !report.summary.isEmpty { line += ": \(report.summary)" }
            lines.append(line)
        }
        if reports.count < total {
            lines.append("- and \(total - reports.count) more")
        }
        lines += ["", "The full reports are JSON files in Settings > Advanced > Diagnostics. Attach them if a maintainer asks."]
        return lines.joined(separator: "\n")
    }

    private static func make(title: String, body: String) -> URL {
        var components = URLComponents(string: newIssueURL)!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: "bug"),
        ]
        return components.url!
    }
}
