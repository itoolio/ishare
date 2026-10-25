import AVFoundation
import Foundation

enum RecordingSegments {
    static func segmentURL(for fileURL: URL, index: Int) -> URL {
        let name = ".\(fileURL.deletingPathExtension().lastPathComponent)-part\(index)-\(UUID().uuidString.prefix(8)).\(fileURL.pathExtension)"
        return fileURL.deletingLastPathComponent().appending(path: name)
    }

    static func concatenate(_ segments: [URL], into destination: URL, fileType: AVFileType) async throws {
        let first = segmentURL(for: destination, index: 0)
        try FileManager.default.moveItem(at: destination, to: first)
        let parts = [first] + segments.dropFirst()
        defer { parts.forEach { try? FileManager.default.removeItem(at: $0) } }
        let composition = AVMutableComposition()
        var cursor = CMTime.zero
        for part in parts where FileManager.default.fileExists(atPath: part.path) {
            let asset = AVURLAsset(url: part)
            guard let duration = try? await asset.load(.duration), duration.isNumeric, duration > .zero else { continue }
            try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: asset, at: cursor)
            cursor = cursor + duration
        }
        guard cursor > .zero, let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            try? FileManager.default.copyItem(at: first, to: destination)
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try await session.export(to: destination, as: fileType)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: first, to: destination)
            throw error
        }
    }
}
