import Defaults
import Foundation

struct HistoryItem: Codable, Hashable, Defaults.Serializable {
    var fileUrl: String?
    var deletionUrl: String?
    var uploaderId: UUID?
    var s3Key: String?
    var localPath: String?
    var date: Date?
    var id: Self { self }
}

func addToUploadHistory(_ item: HistoryItem) {
    NSLog("Adding item to upload history: %@", item.fileUrl ?? "nil")
    var history = Defaults[.uploadHistory]
    history.insert(item, at: 0)
    if history.count > 50 {
        NSLog("Upload history exceeded 50 items, removing oldest entry")
        history.removeLast()
    }
    Defaults[.uploadHistory] = history
}
