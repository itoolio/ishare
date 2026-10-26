import Foundation
import Testing
@testable import ishare

struct HistoryExportTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    var items: [HistoryItem] {
        [
            HistoryItem(
                fileUrl: "https://img.example.com/a.png", deletionUrl: "https://img.example.com/delete/secret", date: date, shortUrl: "https://s.example/a",
                altText: "A \"quoted\" <dashboard>", title: "Dashboard", uploadedSize: 2048
            ),
            HistoryItem(fileUrl: "https://img.example.com/clip.mp4", date: date.addingTimeInterval(-60), uploaderName: "=HYPERLINK(\"https://evil\")"),
            HistoryItem(fileUrl: "javascript:alert(1)", date: date.addingTimeInterval(-120), title: "<script>alert(1)</script>"),
        ]
    }

    func document(includesDeletionLinks: Bool = false) -> HistoryExportDocument {
        HistoryExportDocument(
            records: items.map { HistoryExportRecord.make($0, uploaderName: $0.uploaderName, fileSize: nil) },
            includesDeletionLinks: includesDeletionLinks, generatedAt: date
        )
    }

    @Test func recordsCarryEveryExportedField() {
        let record = HistoryExportRecord.make(items[0], uploaderName: "R2", fileSize: 99)
        #expect(record.link == "https://img.example.com/a.png")
        #expect(record.shortLink == "https://s.example/a")
        #expect(record.deletionLink == "https://img.example.com/delete/secret")
        #expect(record.fileName == "a.png")
        #expect(record.type == "image")
        #expect(record.size == 2048)
        #expect(record.uploader == "R2")
        #expect(record.date == date)
        #expect(HistoryExportRecord.make(items[1], uploaderName: nil, fileSize: 99).size == 99)
        #expect(HistoryExportRecord.make(items[1], uploaderName: nil, fileSize: nil).type == "video")
    }

    @Test func csvLeavesOutDeletionLinksByDefault() {
        let csv = HistoryCSV.render(document())
        let header = csv.components(separatedBy: "\r\n")[0]
        #expect(header == "link,short_link,file_name,title,type,size,uploader,date,alt_text")
        #expect(!csv.contains("delete/secret"))
        let withDeletion = HistoryCSV.render(document(includesDeletionLinks: true))
        #expect(withDeletion.components(separatedBy: "\r\n")[0].contains("deletion_link"))
        #expect(withDeletion.contains("https://img.example.com/delete/secret"))
    }

    @Test func csvQuotesAndNeutralizesFormulas() {
        #expect(HistoryCSV.field("plain") == "plain")
        #expect(HistoryCSV.field("a,b") == "\"a,b\"")
        #expect(HistoryCSV.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(HistoryCSV.field("line\nbreak") == "\"line\nbreak\"")
        #expect(HistoryCSV.field("=1+1") == "'=1+1")
        #expect(HistoryCSV.field("+SUM(A1)") == "'+SUM(A1)")
        #expect(HistoryCSV.field("-2") == "'-2")
        #expect(HistoryCSV.field("@cmd") == "'@cmd")
        #expect(HistoryCSV.field("\tTab") == "'\tTab")
        let csv = HistoryCSV.render(document())
        #expect(csv.contains("\"'=HYPERLINK(\"\"https://evil\"\")\""))
        #expect(csv.contains("\"A \"\"quoted\"\" <dashboard>\""))
        #expect(csv.components(separatedBy: "\r\n").count == items.count + 2)
    }

    @Test func jsonOmitsDeletionLinksUnlessRequested() throws {
        let data = try HistoryJSON.render(document())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let uploads = try #require(object["uploads"] as? [[String: Any]])
        #expect(object["count"] as? Int == 3)
        #expect(uploads.count == 3)
        #expect(uploads[0]["deletionLink"] == nil)
        #expect(uploads[0]["shortLink"] as? String == "https://s.example/a")
        #expect(uploads[0]["altText"] as? String == "A \"quoted\" <dashboard>")
        #expect(uploads[0]["date"] as? String == "2027-01-15T08:00:00Z")
        let withDeletion = try #require(try JSONSerialization.jsonObject(with: HistoryJSON.render(document(includesDeletionLinks: true))) as? [String: Any])
        #expect((withDeletion["uploads"] as? [[String: Any]])?.first?["deletionLink"] as? String == "https://img.example.com/delete/secret")
    }

    @Test func htmlEscapesEverythingAndOnlyLinksWebURLs() {
        let html = HistoryHTML.render(
            document(), thumbnails: [.embedded(Data([1, 2, 3])), .none, .file("../../etc/passwd")], formatSize: { "\($0) B" }, formatDate: { _ in "Jan 15" })
        #expect(!html.contains("<script>alert(1)</script>"))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(!html.contains("href=\"javascript:"))
        #expect(html.contains("alt=\"A &quot;quoted&quot; &lt;dashboard&gt;\""))
        #expect(html.contains("href=\"https://s.example/a\""))
        #expect(html.contains("data:image/jpeg;base64,AQID"))
        #expect(!html.contains("etc/passwd"))
        #expect(!html.contains("delete/secret"))
        #expect(html.contains("=HYPERLINK(&quot;https://evil&quot;)"))
        #expect(html.contains("2048 B"))
        #expect(html.contains("id=\"search\""))
    }

    @Test func htmlIsSelfContainedWithAHashedInlineScript() {
        let html = HistoryHTML.render(document(), thumbnails: [], formatSize: { "\($0)" }, formatDate: { _ in "" })
        #expect(!html.contains("src=\"http"))
        #expect(!html.contains("<link"))
        #expect(!html.contains("<script src"))
        #expect(html.contains("script-src '\(HistoryHTML.scriptHash)'"))
        #expect(html.contains("img-src data:;"))
        #expect(html.contains("<script>\(HistoryHTML.script)</script>"))
        let folder = HistoryHTML.render(document(), thumbnails: [.file("thumbnails/1.jpg")], formatSize: { "\($0)" }, formatDate: { _ in "" })
        #expect(folder.contains("<img src=\"thumbnails/1.jpg\""))
        #expect(folder.contains("img-src data: 'self' file:;"))
    }

    @Test func htmlIncludesDeletionLinksOnlyWhenRequested() {
        let html = HistoryHTML.render(document(includesDeletionLinks: true), thumbnails: [], formatSize: { "\($0)" }, formatDate: { _ in "" })
        #expect(html.contains("https://img.example.com/delete/secret"))
    }

    @Test func safeLinksAndRelativePathsRejectEverythingElse() {
        #expect(HistoryHTML.safeLink("https://example.com/a") == "https://example.com/a")
        #expect(HistoryHTML.safeLink("http://example.com") == "http://example.com")
        for unsafe in ["javascript:alert(1)", "data:text/html,hi", "file:///etc/passwd", "vbscript:x", "", "//example.com"] {
            #expect(HistoryHTML.safeLink(unsafe) == nil)
        }
        #expect(HistoryHTML.safeRelativePath("thumbnails/1.jpg") == "thumbnails/1.jpg")
        for unsafe in ["/abs.jpg", "../up.jpg", "a\"b.jpg", "a b.jpg", "javascript:x"] {
            #expect(HistoryHTML.safeRelativePath(unsafe) == nil)
        }
        #expect(HistoryHTML.escape("<a href='x'>&`") == "&lt;a href=&#39;x&#39;&gt;&amp;&#96;")
    }

    @Test func scopesPickAllFilteredOrSelectedItems() {
        let all = items
        let filtered = [all[0], all[1]]
        let selected = [all[2]]
        #expect(HistoryExportScope.items(.all, all: all, filtered: filtered, selected: selected) == all)
        #expect(HistoryExportScope.items(.filtered, all: all, filtered: filtered, selected: selected) == filtered)
        #expect(HistoryExportScope.items(.selection, all: all, filtered: filtered, selected: selected) == selected)
        let request = HistoryExportRequest(all: all, filtered: filtered, selected: [], filterIsActive: true, uploaderName: { _ in nil })
        #expect(request.availableScopes == [.all, .filtered])
        #expect(request.preferredScope == .filtered)
        let selection = HistoryExportRequest(all: all, filtered: all, selected: selected, filterIsActive: false, uploaderName: { _ in nil })
        #expect(selection.availableScopes == [.all, .selection])
        #expect(selection.preferredScope == .selection)
    }

    @Test func filteredExportsUseTheHistoryFilter() {
        var filter = HistoryFilter()
        filter.kind = .videos
        let filtered = filter.apply(to: items) { $0.uploaderName }
        let csv = HistoryCSV.render(HistoryExportDocument(records: filtered.map { HistoryExportRecord.make($0, uploaderName: nil, fileSize: nil) }))
        #expect(csv.contains("clip.mp4"))
        #expect(!csv.contains("a.png"))
    }

    @Test func writesEveryFormatToDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "history-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appending(path: "local.png")
        let cgImage = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 80, height: 50), hue: 0.3, title: "x"))
        try ImageEncoder.write(cgImage, as: .PNG, to: image)
        let inputs = [HistoryExportWriter.Input(item: HistoryItem(fileUrl: "https://img.example.com/local.png", localPath: image.path, date: date), uploaderName: "Folder")]
        for format in [HistoryExportFormat.csv, .json, .html] {
            let url = directory.appending(path: "export.\(format.fileExtension ?? "")")
            let written = try await HistoryExportWriter.write(inputs, format: format, includesDeletionLinks: false, to: url)
            #expect(FileManager.default.fileExists(atPath: written.path))
        }
        let html = try String(contentsOf: directory.appending(path: "export.html"), encoding: .utf8)
        #expect(html.contains("data:image/jpeg;base64,"))
        let folder = directory.appending(path: "gallery", directoryHint: .isDirectory)
        let index = try await HistoryExportWriter.write(inputs, format: .htmlFolder, includesDeletionLinks: false, to: folder)
        #expect(index.lastPathComponent == "index.html")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "thumbnails/1.jpg").path))
        #expect(try String(contentsOf: index, encoding: .utf8).contains("src=\"thumbnails/1.jpg\""))
    }

    @Test func defaultFileNamesMatchTheFormat() {
        #expect(HistoryExportWriter.defaultFileName(for: .csv, date: date).hasSuffix(".csv"))
        #expect(HistoryExportWriter.defaultFileName(for: .htmlFolder, date: date) == "ishare uploads 2027-01-15")
    }
}
