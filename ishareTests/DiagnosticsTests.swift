import Foundation
import Testing
@testable import ishare

struct DiagnosticsStoreTests {
    let store: DiagnosticsStore
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        let directory = FileManager.default.temporaryDirectory.appending(path: "diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = DiagnosticsStore(directory: directory, limit: 20)
    }

    func diagnostic(_ index: Int) -> Data {
        Data(#"{"callStackTree":{"callStacks":[]},"diagnosticMetaData":{"index":\#(index)}}"#.utf8)
    }

    @discardableResult
    func save(_ index: Int, kind: DiagnosticKind = .crash) throws -> URL {
        try store.save(
            kind: kind, date: start.addingTimeInterval(TimeInterval(index) * 60), summary: "signal \(index)",
            appVersion: "5.2.0", osVersion: "macOS 26.1", diagnostic: diagnostic(index)
        )
    }

    @Test func storesReportsAsJSONWithTheirMetadata() throws {
        let url = try save(1, kind: .hang)
        let reports = store.reports()
        #expect(reports.count == 1)
        let report = try #require(reports.first)
        #expect(report.url.lastPathComponent == url.lastPathComponent)
        #expect(report.kind == .hang)
        #expect(report.date == start.addingTimeInterval(60))
        #expect(report.summary == "signal 1")
        #expect(report.appVersion == "5.2.0")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let embedded = try #require(object["diagnostic"] as? [String: Any])
        #expect((embedded["diagnosticMetaData"] as? [String: Any])?["index"] as? Int == 1)
        #expect(url.path.hasPrefix(store.directory.path))
    }

    @Test func keepsOnlyTheNewestTwentyReports() throws {
        for index in 0 ..< 25 {
            try save(index, kind: DiagnosticKind.allCases[index % DiagnosticKind.allCases.count])
        }
        let reports = store.reports()
        #expect(reports.count == 20)
        #expect(reports.first?.summary == "signal 24")
        #expect(reports.last?.summary == "signal 5")
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.count == 20)
    }

    @Test func savingTheSameDiagnosticTwiceKeepsOneFile() throws {
        let first = try save(3)
        let second = try save(3)
        #expect(first == second)
        #expect(store.reports().count == 1)
    }

    @Test func deleteAllRemovesEveryReport() throws {
        for index in 0 ..< 3 { try save(index) }
        store.deleteAll()
        #expect(store.reports().isEmpty)
    }

    @Test func ignoresFilesThatAreNotReports() throws {
        try save(1)
        try Data("not json".utf8).write(to: store.directory.appending(path: "broken.json"))
        try Data("notes".utf8).write(to: store.directory.appending(path: "notes.txt"))
        #expect(store.reports().count == 1)
    }
}

struct DiagnosticsIssueTests {
    func report(_ index: Int, summary: String = "signal 11") -> DiagnosticReport {
        DiagnosticReport(
            url: URL(fileURLWithPath: "/tmp/\(index).json"), kind: .crash, date: Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(index)),
            summary: summary, appVersion: "5.2.0", osVersion: "macOS 26.1"
        )
    }

    func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func prefillsAGitHubIssueWithTheReports() {
        let url = DiagnosticsIssue.url(reports: [report(1), report(0)], appVersion: "5.2.0", osVersion: "Version 26.1")
        #expect(url.absoluteString.hasPrefix("https://github.com/itoolio/ishare/issues/new?"))
        let fields = query(url)
        #expect(fields["title"] == "Diagnostics: crash in ishare 5.2.0")
        #expect(fields["labels"] == "bug")
        let body = fields["body"] ?? ""
        #expect(body.contains("- ishare: 5.2.0"))
        #expect(body.contains("- macOS: Version 26.1"))
        #expect(body.contains("crash in 5.2.0: signal 11"))
    }

    @Test func dropsReportsToStayWithinTheURLLimit() {
        let reports = (0 ..< 40).map { report($0, summary: String(repeating: "frame ", count: 40)) }
        let url = DiagnosticsIssue.url(reports: reports, appVersion: "5.2.0", osVersion: "26.1", maximumLength: 4000)
        #expect(url.absoluteString.count <= 4000)
        #expect(query(url)["body"]?.contains("more") == true)
    }

    @Test func worksWithoutReports() {
        let fields = query(DiagnosticsIssue.url(reports: [], appVersion: "5.2.0", osVersion: "26.1"))
        #expect(fields["title"] == "Bug report for ishare 5.2.0")
        #expect(fields["body"]?.contains("No crash or hang reports") == true)
    }
}
