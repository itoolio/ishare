import CryptoKit
import Foundation
import ishareCore

enum HistoryExportFormat: String, CaseIterable, Identifiable, Sendable {
    case html
    case htmlFolder
    case csv
    case json

    var id: Self { self }

    var title: String {
        switch self {
        case .html: "HTML gallery (single file)"
        case .htmlFolder: "HTML gallery (folder with thumbnails)"
        case .csv: "CSV"
        case .json: "JSON"
        }
    }

    var fileExtension: String? {
        switch self {
        case .html: "html"
        case .htmlFolder: nil
        case .csv: "csv"
        case .json: "json"
        }
    }

    var isGallery: Bool { self == .html || self == .htmlFolder }
}

enum HistoryExportScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case filtered
    case selection

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All uploads"
        case .filtered: "Uploads matching the current filter"
        case .selection: "Selected uploads"
        }
    }

    static func items(_ scope: HistoryExportScope, all: [HistoryItem], filtered: [HistoryItem], selected: [HistoryItem]) -> [HistoryItem] {
        switch scope {
        case .all: all
        case .filtered: filtered
        case .selection: selected
        }
    }
}

struct HistoryExportRecord: Codable, Equatable, Sendable {
    var link: String?
    var shortLink: String?
    var deletionLink: String?
    var fileName: String
    var title: String?
    var type: String
    var size: Int?
    var uploader: String?
    var date: Date?
    var altText: String?

    static func make(_ item: HistoryItem, uploaderName: String?, fileSize: Int?) -> HistoryExportRecord {
        HistoryExportRecord(
            link: item.fileUrl, shortLink: item.shortUrl, deletionLink: item.deletionUrl, fileName: item.fileName, title: item.title,
            type: item.kind.rawValue, size: item.uploadedSize ?? fileSize ?? item.originalSize, uploader: uploaderName, date: item.date,
            altText: item.altText
        )
    }
}

struct HistoryExportDocument: Sendable {
    var records: [HistoryExportRecord]
    var includesDeletionLinks = false
    var generatedAt = Date()
    var title = "ishare uploads"
}

enum HistoryCSV {
    static let columns = ["link", "short_link", "deletion_link", "file_name", "title", "type", "size", "uploader", "date", "alt_text"]

    static func render(_ document: HistoryExportDocument) -> String {
        let header = columns.filter { document.includesDeletionLinks || $0 != "deletion_link" }
        var lines = [header.map(field).joined(separator: ",")]
        for record in document.records {
            var values: [String?] = [record.link, record.shortLink]
            if document.includesDeletionLinks {
                values.append(record.deletionLink)
            }
            values += [
                record.fileName, record.title, record.type, record.size.map(String.init), record.uploader,
                record.date.map(HistoryExportDates.iso8601), record.altText,
            ]
            lines.append(values.map { field($0 ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static let formulaPrefixes: Set<Character> = ["=", "+", "-", "@", "\t", "\r", "|", "%"]

    static func neutralized(_ value: String) -> String {
        guard let first = value.first, formulaPrefixes.contains(first) else { return value }
        return "'" + value
    }

    static func field(_ raw: String) -> String {
        let value = neutralized(raw)
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == ";" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

enum HistoryJSON {
    struct Envelope: Encodable {
        let generator: String
        let generatedAt: Date
        let count: Int
        let uploads: [Entry]
    }

    struct Entry: Encodable {
        let link: String?
        let shortLink: String?
        let deletionLink: String?
        let fileName: String
        let title: String?
        let type: String
        let size: Int?
        let uploader: String?
        let date: Date?
        let altText: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(link, forKey: .link)
            try container.encode(shortLink, forKey: .shortLink)
            try container.encodeIfPresent(deletionLink, forKey: .deletionLink)
            try container.encode(fileName, forKey: .fileName)
            try container.encode(title, forKey: .title)
            try container.encode(type, forKey: .type)
            try container.encode(size, forKey: .size)
            try container.encode(uploader, forKey: .uploader)
            try container.encode(date, forKey: .date)
            try container.encode(altText, forKey: .altText)
        }

        enum CodingKeys: String, CodingKey {
            case link, shortLink, deletionLink, fileName, title, type, size, uploader, date, altText
        }
    }

    static func render(_ document: HistoryExportDocument) throws -> Data {
        let entries = document.records.map { record in
            Entry(
                link: record.link, shortLink: record.shortLink, deletionLink: document.includesDeletionLinks ? record.deletionLink : nil,
                fileName: record.fileName, title: record.title, type: record.type, size: record.size, uploader: record.uploader, date: record.date,
                altText: record.altText
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Envelope(generator: "ishare", generatedAt: document.generatedAt, count: entries.count, uploads: entries))
    }
}

enum HistoryExportDates {
    static func iso8601(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

enum HistoryHTML {
    enum Thumbnail: Equatable, Sendable {
        case embedded(Data)
        case file(String)
        case none
    }

    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            case "`": escaped += "&#96;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    static func safeLink(_ value: String?) -> String? {
        guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil
        else { return nil }
        return url.absoluteString
    }

    static func safeRelativePath(_ path: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(".."), path.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return path
    }

    static let script = """
        (function () {
          var input = document.getElementById("search");
          var cards = Array.prototype.slice.call(document.querySelectorAll(".card"));
          var count = document.getElementById("count");
          function update() {
            var tokens = input.value.toLowerCase().split(/\\s+/).filter(Boolean);
            var shown = 0;
            cards.forEach(function (card) {
              var text = card.getAttribute("data-search") || "";
              var visible = tokens.every(function (token) { return text.indexOf(token) !== -1; });
              card.hidden = !visible;
              if (visible) { shown += 1; }
            });
            count.textContent = String(shown);
          }
          input.addEventListener("input", update);
          update();
        })();
        """

    static let style = """
        :root { color-scheme: light dark; --bg: #f6f6f8; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --accent: #0a84ff; --border: rgba(0,0,0,.08); }
        @media (prefers-color-scheme: dark) { :root { --bg: #161618; --card: #232326; --text: #f5f5f7; --muted: #a1a1a6; --border: rgba(255,255,255,.1); } }
        * { box-sizing: border-box; }
        body { margin: 0; font: 15px/1.4 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; background: var(--bg); color: var(--text); }
        header { position: sticky; top: 0; display: flex; flex-wrap: wrap; gap: 12px; align-items: center; padding: 16px; background: var(--bg); border-bottom: 1px solid var(--border); z-index: 1; }
        h1 { margin: 0; font-size: 20px; flex: 1 1 auto; }
        input[type=search] { flex: 1 1 240px; max-width: 420px; padding: 8px 12px; border-radius: 10px; border: 1px solid var(--border); background: var(--card); color: inherit; font: inherit; }
        .meta { color: var(--muted); font-size: 13px; }
        main { display: grid; gap: 16px; padding: 16px; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); }
        .card { background: var(--card); border: 1px solid var(--border); border-radius: 14px; overflow: hidden; display: flex; flex-direction: column; }
        .card[hidden] { display: none; }
        .thumb { aspect-ratio: 16 / 10; background: var(--border); display: flex; align-items: center; justify-content: center; color: var(--muted); }
        .thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
        .body { padding: 10px 12px 12px; display: flex; flex-direction: column; gap: 4px; min-width: 0; }
        .name { font-weight: 600; overflow-wrap: anywhere; }
        .name a { color: inherit; text-decoration: none; }
        .name a:hover { color: var(--accent); }
        .alt { font-size: 13px; color: var(--muted); }
        .links a { color: var(--accent); font-size: 13px; margin-right: 10px; }
        """

    static var scriptHash: String {
        "sha256-" + Data(SHA256.hash(data: Data(script.utf8))).base64EncodedString()
    }

    static func render(_ document: HistoryExportDocument, thumbnails: [Thumbnail], formatSize: (Int) -> String, formatDate: (Date) -> String) -> String {
        let cards = document.records.enumerated().map { index, record in
            card(
                record, thumbnail: thumbnails.indices.contains(index) ? thumbnails[index] : .none, includesDeletionLink: document.includesDeletionLinks, formatSize: formatSize,
                formatDate: formatDate)
        }
        let title = escape(document.title)
        let imageSources = thumbnails.contains { if case .file = $0 { true } else { false } } ? "data: 'self' file:" : "data:"
        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="referrer" content="no-referrer">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(imageSources); style-src 'unsafe-inline'; script-src '\(scriptHash)'; base-uri 'none'; form-action 'none'">
            <meta name="generator" content="ishare">
            <title>\(title)</title>
            <style>
            \(style)
            </style>
            </head>
            <body>
            <header>
            <h1>\(title)</h1>
            <input id="search" type="search" placeholder="Search" aria-label="Search" autocomplete="off">
            <span class="meta"><span id="count">\(document.records.count)</span> / \(document.records.count) · \(escape(formatDate(document.generatedAt)))</span>
            </header>
            <main>
            \(cards.joined(separator: "\n"))
            </main>
            <script>\(script)</script>
            </body>
            </html>

            """
    }

    static func card(_ record: HistoryExportRecord, thumbnail: Thumbnail, includesDeletionLink: Bool, formatSize: (Int) -> String, formatDate: (Date) -> String) -> String {
        let link = safeLink(record.shortLink) ?? safeLink(record.link)
        let altText = record.altText.flatMap { $0.isEmpty ? nil : $0 }
        let alt = escape(altText ?? record.title ?? record.fileName)
        let image: String =
            switch thumbnail {
            case let .embedded(data): "<img src=\"data:image/jpeg;base64,\(data.base64EncodedString())\" alt=\"\(alt)\" loading=\"lazy\">"
            case let .file(path): safeRelativePath(path).map { "<img src=\"\(escape($0))\" alt=\"\(alt)\" loading=\"lazy\">" } ?? escape(record.type)
            case .none: escape(record.type)
            }
        let name = escape(record.title.flatMap { $0.isEmpty ? nil : $0 } ?? record.fileName)
        let heading = link.map { "<a href=\"\(escape($0))\" rel=\"noopener noreferrer\">\(name)</a>" } ?? name
        let details = [record.uploader, record.date.map(formatDate), record.size.map(formatSize)].compactMap { $0 }.map(escape).joined(separator: " · ")
        var links: [String] = []
        if let full = safeLink(record.link) {
            links.append("<a href=\"\(escape(full))\" rel=\"noopener noreferrer\">Link</a>")
        }
        if let short = safeLink(record.shortLink) {
            links.append("<a href=\"\(escape(short))\" rel=\"noopener noreferrer\">Short link</a>")
        }
        if includesDeletionLink, let deletion = safeLink(record.deletionLink) {
            links.append("<a href=\"\(escape(deletion))\" rel=\"noopener noreferrer\">Deletion link</a>")
        }
        let search = escape(
            [record.fileName, record.title, record.uploader, record.altText, record.link, record.shortLink, record.type, record.date.map(formatDate)].compactMap { $0 }.joined(
                separator: " "
            ).lowercased())
        var body = ["<div class=\"name\">\(heading)</div>"]
        if !details.isEmpty {
            body.append("<div class=\"meta\">\(details)</div>")
        }
        if let altText {
            body.append("<div class=\"alt\">\(escape(altText))</div>")
        }
        if !links.isEmpty {
            body.append("<div class=\"links\">\(links.joined())</div>")
        }
        return "<article class=\"card\" data-search=\"\(search)\"><div class=\"thumb\">\(image)</div><div class=\"body\">\(body.joined())</div></article>"
    }
}
