import Foundation

public enum CloudProvider: String, Codable, CaseIterable, Sendable {
    case dropbox
    case googleDrive = "googledrive"
    case oneDrive = "onedrive"

    static let redirectScheme = "ishare-oauth"
    static let googleSchemePrefix = "com.googleusercontent.apps."

    public var kind: UploaderKind {
        switch self {
        case .dropbox: .dropbox
        case .googleDrive: .googleDrive
        case .oneDrive: .oneDrive
        }
    }

    public var title: String { kind.titleKey }

    var infoPlistKey: String {
        switch self {
        case .dropbox: "ISHAREDropboxClientID"
        case .googleDrive: "ISHAREGoogleClientID"
        case .oneDrive: "ISHAREOneDriveClientID"
        }
    }

    public var builtInClientID: String? {
        Self.clientID(fromInfoValue: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    public var hasBuiltInClientID: Bool { builtInClientID != nil }

    public static func clientID(fromInfoValue value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    public var authorizationEndpoint: URL {
        switch self {
        case .dropbox: URL(string: "https://www.dropbox.com/oauth2/authorize")!
        case .googleDrive: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        case .oneDrive: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
        }
    }

    public var tokenEndpoint: URL {
        switch self {
        case .dropbox: URL(string: "https://api.dropboxapi.com/oauth2/token")!
        case .googleDrive: URL(string: "https://oauth2.googleapis.com/token")!
        case .oneDrive: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
        }
    }

    public var scopes: [String] {
        switch self {
        case .dropbox: ["account_info.read", "files.content.write", "files.content.read", "sharing.write", "sharing.read"]
        case .googleDrive: ["https://www.googleapis.com/auth/drive.file"]
        case .oneDrive: ["Files.ReadWrite", "User.Read", "offline_access"]
        }
    }

    public var extraAuthorizationParameters: [(String, String)] {
        switch self {
        case .dropbox: [("token_access_type", "offline")]
        case .googleDrive: [("access_type", "offline"), ("prompt", "consent")]
        case .oneDrive: [("prompt", "select_account")]
        }
    }

    public func callbackScheme(clientID: String) -> String {
        switch self {
        case .googleDrive: Self.googleSchemePrefix + Self.googleClientPrefix(clientID)
        case .dropbox, .oneDrive: Self.redirectScheme
        }
    }

    public func redirectURI(clientID: String) -> String {
        switch self {
        case .googleDrive: callbackScheme(clientID: clientID) + ":/oauth2redirect"
        case .dropbox: "\(Self.redirectScheme)://dropbox"
        case .oneDrive: "\(Self.redirectScheme)://onedrive"
        }
    }

    static func googleClientPrefix(_ clientID: String) -> String {
        let suffix = ".apps.googleusercontent.com"
        return clientID.hasSuffix(suffix) ? String(clientID.dropLast(suffix.count)) : clientID
    }
}
