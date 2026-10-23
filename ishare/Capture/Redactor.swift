import CoreGraphics
import Defaults
import Foundation

enum RedactionCategory: String, CaseIterable, Codable, Identifiable, Sendable, Defaults.Serializable {
    case emailAddresses
    case apiKeys
    case creditCards
    case ipAddresses
    case phoneNumbers

    var id: Self { self }

    var title: String {
        switch self {
        case .emailAddresses: "Email addresses"
        case .apiKeys: "API keys and tokens"
        case .creditCards: "Credit card numbers"
        case .ipAddresses: "IP addresses"
        case .phoneNumbers: "Phone numbers"
        }
    }
}

enum Luhn {
    static func isValid(_ number: String) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard (13 ... 19).contains(digits.count), digits.count == number.filter({ !$0.isWhitespace && $0 != "-" }).count else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, entry in
            let isDoubled = !entry.offset.isMultiple(of: 2)
            let value = isDoubled ? entry.element * 2 : entry.element
            return total + (value > 9 ? value - 9 : value)
        }
        return sum.isMultiple(of: 10)
    }
}

enum SensitiveTextMatcher {
    static func matches(in text: String, categories: Set<RedactionCategory>) -> [NSRange] {
        merged(categories.flatMap { matches(in: text, category: $0) })
    }

    static func matches(in text: String, category: RedactionCategory) -> [NSRange] {
        switch category {
        case .emailAddresses: ranges(of: emailPattern, in: text)
        case .apiKeys: tokenRanges(in: text)
        case .creditCards: ranges(of: cardCandidatePattern, in: text).filter { Luhn.isValid(substring(text, $0)) }
        case .ipAddresses: ranges(of: ipv4Pattern, in: text) + ranges(of: ipv6Pattern, in: text).filter { isPlausibleIPv6(substring(text, $0)) }
        case .phoneNumbers: phoneRanges(in: text)
        }
    }

    static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,}"#
    static let cardCandidatePattern = #"(?<![\d-])\d(?:[ -]?\d){12,18}(?![\d-])"#
    static let ipv4Pattern = #"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?![\d.])"#
    static let ipv6Pattern = #"(?<![0-9A-F:])(?:(?:[0-9A-F]{1,4}:){7}[0-9A-F]{1,4}|(?:[0-9A-F]{1,4}:){1,6}:(?:[0-9A-F]{1,4}(?::[0-9A-F]{1,4}){0,5})?)(?![0-9A-F:])"#

    static let knownTokenPatterns = [
        #"sk-(?:ant-|proj-|live-|test-)?[A-Za-z0-9_-]{20,}"#,
        #"(?:gh[pousr]|github_pat)_[A-Za-z0-9_]{20,}"#,
        #"xox[abposr]-[A-Za-z0-9-]{10,}"#,
        #"(?:AKIA|ASIA)[0-9A-Z]{16}"#,
        #"AIza[0-9A-Za-z_-]{35}"#,
        #"(?:sk|pk|rk)_(?:live|test)_[0-9A-Za-z]{16,}"#,
        #"glpat-[0-9A-Za-z_-]{20,}"#,
        #"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,
    ]
    static let assignedSecretPattern = #"(?:api[_-]?key|token|secret|password|passwd|bearer|authorization)["']?\s*[:=]?\s*["']?([A-Za-z0-9_\-./+=]{12,})"#
    static let genericTokenPattern = #"(?<![A-Za-z0-9_-])(?=[A-Za-z0-9_-]*[a-z])(?=[A-Za-z0-9_-]*[A-Z])(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{32,}(?![A-Za-z0-9_-])"#

    static func tokenRanges(in text: String) -> [NSRange] {
        knownTokenPatterns.flatMap { ranges(of: $0, in: text, caseInsensitive: false) }
            + ranges(of: assignedSecretPattern, in: text, captureGroup: 1)
            + ranges(of: genericTokenPattern, in: text, caseInsensitive: false)
    }

    static func isPlausibleIPv6(_ candidate: String) -> Bool {
        candidate.contains(where: \.isNumber) && candidate.split(separator: ":").count >= 2
    }

    static func phoneRanges(in text: String) -> [NSRange] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map(\.range)
            .filter { substring(text, $0).filter(\.isNumber).count >= 7 }
    }

    static func ranges(of pattern: String, in text: String, caseInsensitive: Bool = true, captureGroup: Int = 0) -> [NSRange] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { $0.range(at: captureGroup) }
            .filter { $0.location != NSNotFound && $0.length > 0 }
    }

    static func substring(_ text: String, _ range: NSRange) -> String {
        Range(range, in: text).map { String(text[$0]) } ?? ""
    }

    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        ranges.sorted { $0.location < $1.location }.reduce(into: []) { result, range in
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
    }
}

enum RedactionGeometry {
    static func imageRect(forNormalized box: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: box.minX * imageSize.width,
            y: (1 - box.maxY) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
    }

    static func normalizedBox(for range: NSRange, in line: RecognizedLine) -> CGRect {
        let words = line.words.filter { NSIntersectionRange($0.range, range).length > 0 }
        if let first = words.first {
            return words.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
        }
        let length = max(1, (line.text as NSString).length)
        let start = CGFloat(range.location) / CGFloat(length)
        let end = CGFloat(NSMaxRange(range)) / CGFloat(length)
        let box = line.boundingBox
        return CGRect(x: box.minX + box.width * start, y: box.minY, width: box.width * (end - start), height: box.height)
    }

    static func rects(for lines: [RecognizedLine], categories: Set<RedactionCategory>, imageSize: CGSize) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: imageSize)
        return lines.flatMap { line in
            SensitiveTextMatcher.matches(in: line.text, categories: categories).map { range in
                let rect = imageRect(forNormalized: normalizedBox(for: range, in: line), imageSize: imageSize)
                let padding = max(2, rect.height * 0.15)
                return rect.insetBy(dx: -padding, dy: -padding).intersection(bounds).integral
            }
        }
        .filter { !$0.isNull && $0.width >= 1 && $0.height >= 1 }
    }
}

enum Redactor {
    static func redact(_ image: CGImage, rects: [CGRect]) -> CGImage {
        rects.reduce(image) { result, rect in
            ImageProcessing.pixelate(result, region: rect, blockSize: max(8, rect.height / 1.5))
        }
    }

    static func redactedCopy(of fileURL: URL, categories: Set<RedactionCategory>) async throws -> URL? {
        guard !categories.isEmpty, let image = ImageEncoder.loadImage(at: fileURL) else { return nil }
        let lines = try await TextRecognition.lines(in: image)
        let rects = RedactionGeometry.rects(for: lines, categories: categories, imageSize: CGSize(width: image.width, height: image.height))
        guard !rects.isEmpty else { return nil }
        let fileType = FileType(rawValue: fileURL.pathExtension.lowercased()) ?? .PNG
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-redacted-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: fileURL.deletingPathExtension().lastPathComponent + "." + fileType.rawValue)
        try ImageEncoder.write(redact(image, rects: rects), as: fileType, to: destination)
        return destination
    }

    static func discard(_ redactedURL: URL) {
        try? FileManager.default.removeItem(at: redactedURL.deletingLastPathComponent())
    }

    @MainActor
    static func preparedUploadURL(for fileURL: URL) async -> URL? {
        guard Defaults[.redactBeforeUpload] else { return nil }
        do {
            guard let redacted = try await redactedCopy(of: fileURL, categories: Defaults[.redactionCategories]) else { return nil }
            guard Defaults[.redactSavedFile] else { return redacted }
            _ = try? FileManager.default.replaceItemAt(fileURL, withItemAt: redacted)
            discard(redacted)
            return nil
        } catch {
            Log.capture.error("Redaction failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
