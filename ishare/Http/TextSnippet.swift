import Foundation

enum TextSnippet {
    private struct Rule: Sendable {
        let fileExtension: String
        let matches: @Sendable (String, [Substring]) -> Bool
    }

    private static func anyLine<Output>(_ lines: [Substring], _ pattern: Regex<Output>) -> Bool {
        lines.contains { $0.wholeMatch(of: pattern) != nil }
    }

    private static func lineCount<Output>(_ lines: [Substring], _ pattern: Regex<Output>) -> Int {
        lines.count(where: { $0.wholeMatch(of: pattern) != nil })
    }

    private static let rules: [Rule] = [
        Rule(fileExtension: "json") { text, _ in
            guard let first = text.first, first == "{" || first == "[" else { return false }
            return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
        },
        Rule(fileExtension: "html") { text, _ in
            let lowered = text.prefix(200).lowercased()
            return lowered.hasPrefix("<!doctype html") || lowered.hasPrefix("<html")
        },
        Rule(fileExtension: "xml") { text, _ in text.hasPrefix("<?xml") },
        Rule(fileExtension: "py") { text, lines in
            text.hasPrefix("#!") && lines.first?.contains("python") == true
                || anyLine(lines, /\s*def \w+\(.*\)\s*(->\s*[^:]+)?:\s*/)
                || anyLine(lines, /from [\w.]+ import .+/)
        },
        Rule(fileExtension: "sh") { text, lines in
            text.hasPrefix("#!") && (lines.first?.contains("sh") == true)
        },
        Rule(fileExtension: "js") { text, lines in
            text.hasPrefix("#!") && lines.first?.contains("node") == true
                || anyLine(lines, /\s*(export\s+)?(const|let|var) \w+\s*=\s*(require\(|\(.*\)\s*=>|function).*/)
                || anyLine(lines, /\s*(export\s+)?(async\s+)?function\s*\w*\s*\(.*/)
                || text.contains("console.log(")
        },
        Rule(fileExtension: "swift") { _, lines in
            anyLine(lines, /import (SwiftUI|Foundation|UIKit|AppKit|Combine|XCTest|Testing)/)
                || anyLine(lines, /\s*(@\w+\s+)*(public |private |internal |fileprivate |static )*func \w+(<.*>)?\(.*\).*\{\s*/)
                    && anyLine(lines, /\s*(let|var|guard|return) .*/)
        },
        Rule(fileExtension: "go") { _, lines in
            anyLine(lines, /package \w+/) && anyLine(lines, /func .*\{\s*/)
        },
        Rule(fileExtension: "rs") { _, lines in
            anyLine(lines, /\s*(pub )?fn \w+.*\{\s*/) && (anyLine(lines, /\s*let mut .*/) || anyLine(lines, /use \w+(::\w+)+.*;/))
        },
        Rule(fileExtension: "sql") { _, lines in
            anyLine(lines, /(?i)\s*(select .+ from|insert into|update \w+ set|create table|delete from) .*/)
        },
        Rule(fileExtension: "css") { _, lines in
            anyLine(lines, /\s*[.#]?[\w-]+(\s*[,>+~ ]\s*[.#]?[\w-]+)*\s*\{\s*/) && anyLine(lines, /\s*[\w-]+\s*:\s*[^;]+;\s*/)
        },
        Rule(fileExtension: "md") { text, lines in
            text.contains("```")
                || anyLine(lines, /#{1,6} \S.*/)
                || anyLine(lines, /.*\[[^\]]+\]\([^)]+\).*/)
                || lineCount(lines, /\s*([-*+]|\d+\.) .+/) >= 2 && anyLine(lines, /.*(\*\*|__|`).+(\*\*|__|`).*/)
        },
    ]

    static func fileExtension(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "txt" }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        return rules.first { $0.matches(trimmed, lines) }?.fileExtension ?? "txt"
    }

    static func write(_ text: String, in directory: URL, prefix: String, date: Date = .init()) throws -> URL {
        let name = CaptureFileName.make(prefix: prefix, suffix: "paste", ext: fileExtension(for: text), date: date)
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
