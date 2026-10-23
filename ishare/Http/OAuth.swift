import Alamofire
import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import ishareCore

struct OAuthToken: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var account: String?

    func needsRefresh(at date: Date, leeway: TimeInterval = 120) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(date) < leeway
    }
}

enum OAuthError: LocalizedError, Equatable {
    case missingClientID(String)
    case notSignedIn(String)
    case cancelled
    case stateMismatch
    case missingCode(String?)
    case tokenResponse(String)
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingClientID(provider):
            String(format: "%@ needs a client ID. Paste the client ID of your own app in the uploader settings.".localized(), provider)
        case let .notSignedIn(name):
            String(format: "“%@” isn't signed in. Edit the uploader and sign in again.".localized(), name)
        case .cancelled:
            "Sign-in was cancelled".localized()
        case .stateMismatch:
            "The sign-in response didn't match the request. Try signing in again.".localized()
        case let .missingCode(detail):
            String(format: "The sign-in didn't return an authorization code (%@)".localized(), detail ?? "-")
        case let .tokenResponse(detail):
            String(format: "The token response couldn't be read (%@)".localized(), detail)
        case let .refreshFailed(detail):
            String(format: "Refreshing the sign-in failed. Sign in again in the uploader settings. (%@)".localized(), detail)
        }
    }
}

enum OAuthRequests {
    static func authorizationURL(provider: CloudProvider, clientID: String, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: provider.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: provider.redirectURI(clientID: clientID)),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: provider.scopes.joined(separator: " ")),
        ]
        items += provider.extraAuthorizationParameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        components.queryItems = items
        return components.url!
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    static func tokenRequest(provider: CloudProvider, clientID: String, code: String, verifier: String) -> URLRequest {
        formRequest(
            provider.tokenEndpoint,
            fields: [
                ("grant_type", "authorization_code"),
                ("code", code),
                ("client_id", clientID),
                ("redirect_uri", provider.redirectURI(clientID: clientID)),
                ("code_verifier", verifier),
            ])
    }

    static func refreshRequest(provider: CloudProvider, clientID: String, refreshToken: String) -> URLRequest {
        var fields = [("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", clientID)]
        if provider == .oneDrive {
            fields.append(("scope", provider.scopes.joined(separator: " ")))
        }
        return formRequest(provider.tokenEndpoint, fields: fields)
    }

    static func formRequest(_ url: URL, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(fields)
        return request
    }

    static func token(from data: Data, now: Date = .init(), previous: OAuthToken? = nil) throws -> OAuthToken {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.tokenResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard let accessToken = object["access_token"] as? String, !accessToken.isEmpty else {
            let detail = (object["error_description"] as? String) ?? (object["error"] as? String) ?? "access_token"
            throw OAuthError.tokenResponse(detail)
        }
        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? (object["expires_in"] as? String).flatMap(Double.init)
        return OAuthToken(
            accessToken: accessToken,
            refreshToken: (object["refresh_token"] as? String) ?? previous?.refreshToken,
            expiresAt: expiresIn.map { now.addingTimeInterval($0) },
            account: previous?.account
        )
    }

    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        let items = (components?.queryItems ?? []) + (URLComponents(string: "?" + (components?.fragment ?? ""))?.queryItems ?? [])
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? OAuthError.cancelled : OAuthError.missingCode(value("error_description") ?? error)
        }
        guard value("state") == expectedState else { throw OAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw OAuthError.missingCode(nil) }
        return code
    }
}

enum OAuthTokenStore {
    static func token(for id: UUID) -> OAuthToken? {
        guard let json = UploaderSecrets.read(.oauthToken, for: id) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(OAuthToken.self, from: Data(json.utf8))
    }

    static func save(_ token: OAuthToken?, for id: UUID) throws {
        guard let token else {
            try UploaderSecrets.write(nil, .oauthToken, for: id)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        try UploaderSecrets.write(String(decoding: try encoder.encode(token), as: UTF8.self), .oauthToken, for: id)
    }
}

@MainActor
enum OAuthSession {
    static var now: @Sendable () -> Date = { Date() }
    private static var refreshes: [UUID: Task<OAuthToken, any Error>] = [:]

    static func clientID(provider: CloudProvider, configuration: CloudStorageConfiguration?) throws -> String {
        if let custom = configuration?.clientID?.trimmingCharacters(in: .whitespaces), !custom.isEmpty { return custom }
        guard let builtIn = provider.builtInClientID else { throw OAuthError.missingClientID(provider.title.localized()) }
        return builtIn
    }

    static func exchange(code: String, verifier: String, provider: CloudProvider, clientID: String) async throws -> OAuthToken {
        let request = OAuthRequests.tokenRequest(provider: provider, clientID: clientID, code: code, verifier: verifier)
        let data = try await UploadService.response(of: UploadService.session.request(request))
        return try OAuthRequests.token(from: data, now: now())
    }

    static func refresh(_ token: OAuthToken, provider: CloudProvider, clientID: String) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else { throw OAuthError.refreshFailed("no refresh token") }
        let request = OAuthRequests.refreshRequest(provider: provider, clientID: clientID, refreshToken: refreshToken)
        do {
            let data = try await UploadService.response(of: UploadService.session.request(request))
            return try OAuthRequests.token(from: data, now: now(), previous: token)
        } catch let failure as UploadFailure {
            throw OAuthError.refreshFailed(failure.localizedDescription)
        }
    }

    static func accessToken(for uploader: CustomUploader, provider: CloudProvider, forceRefresh: Bool = false) async throws -> String {
        guard let token = OAuthTokenStore.token(for: uploader.id) else { throw OAuthError.notSignedIn(uploader.name) }
        guard forceRefresh || token.needsRefresh(at: now()) else { return token.accessToken }
        if let running = refreshes[uploader.id] {
            return try await running.value.accessToken
        }
        let clientID = try clientID(provider: provider, configuration: uploader.cloud)
        let id = uploader.id
        let task = Task { @MainActor in
            let refreshed = try await refresh(token, provider: provider, clientID: clientID)
            try OAuthTokenStore.save(refreshed, for: id)
            return refreshed
        }
        refreshes[id] = task
        defer { refreshes[id] = nil }
        return try await task.value.accessToken
    }

    static func withAccessToken<T>(
        for uploader: CustomUploader, provider: CloudProvider, _ body: (String) async throws -> T
    ) async throws -> T {
        let token = try await accessToken(for: uploader, provider: provider)
        do {
            return try await body(token)
        } catch let UploadFailure.http(status, _) where status == 401 {
            let refreshed = try await accessToken(for: uploader, provider: provider, forceRefresh: true)
            return try await body(refreshed)
        }
    }
}

@MainActor
final class WebAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthenticationPresenter()

    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
        }
    }
}

@MainActor
enum WebAuthentication {
    private static var active: ASWebAuthenticationSession?

    static func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callbackURL, error in
                Task { @MainActor in
                    active = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error ?? OAuthError.cancelled)
                    }
                }
            }
            session.presentationContextProvider = WebAuthenticationPresenter.shared
            active = session
            if !session.start() {
                active = nil
                continuation.resume(throwing: OAuthError.cancelled)
            }
        }
    }
}

@MainActor
enum OAuthSignIn {
    static func signIn(provider: CloudProvider, configuration: CloudStorageConfiguration?, uploaderID: UUID) async throws -> OAuthToken {
        let clientID = try OAuthSession.clientID(provider: provider, configuration: configuration)
        let pkce = PKCE.generate()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        let url = OAuthRequests.authorizationURL(provider: provider, clientID: clientID, pkce: pkce, state: state)
        let callback = try await WebAuthentication.authenticate(url: url, callbackScheme: provider.callbackScheme(clientID: clientID))
        let code = try OAuthRequests.authorizationCode(from: callback, expectedState: state)
        var token = try await OAuthSession.exchange(code: code, verifier: pkce.verifier, provider: provider, clientID: clientID)
        token.account = try? await CloudAccounts.accountName(provider: provider, accessToken: token.accessToken)
        try OAuthTokenStore.save(token, for: uploaderID)
        return token
    }

    static func signOut(uploaderID: UUID) {
        try? OAuthTokenStore.save(nil, for: uploaderID)
    }
}
