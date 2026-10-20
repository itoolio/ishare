import OSLog

enum Log {
    static let capture = Logger(subsystem: "dev.adrian.ishare", category: "capture")
    static let upload = Logger(subsystem: "dev.adrian.ishare", category: "upload")
    static let app = Logger(subsystem: "dev.adrian.ishare", category: "app")
}
