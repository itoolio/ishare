import Foundation
import ishareCore

enum TestUploaders {
    static func http(name: String, host: String, responseURL: String = "{{url}}") -> CustomUploader {
        CustomUploader(
            name: name, requestURL: "https://\(host)/upload", headers: nil, formData: nil, fileFormName: "file",
            responseURL: responseURL
        )
    }
}
