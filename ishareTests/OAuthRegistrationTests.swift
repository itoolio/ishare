import Foundation
import ishareCore
import Testing
@testable import ishare

struct OAuthRegistrationTests {
    let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

    @Test func buildsTheExactDropboxAuthorizeURL() {
        let url = OAuthRequests.authorizationURL(provider: .dropbox, clientID: "abc123", pkce: pkce, state: "st")
        #expect(
            url.absoluteString
                == "https://www.dropbox.com/oauth2/authorize?client_id=abc123&response_type=code&redirect_uri=ishare-oauth://dropbox"
                + "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=st"
                + "&scope=account_info.read%20files.content.write%20files.content.read%20sharing.write%20sharing.read&token_access_type=offline")
        #expect(CloudProvider.dropbox.callbackScheme(clientID: "abc123") == "ishare-oauth")
    }

    @Test func buildsTheExactGoogleAuthorizeURLWithTheReversedClientID() {
        let url = OAuthRequests.authorizationURL(provider: .googleDrive, clientID: "123-abc.apps.googleusercontent.com", pkce: pkce, state: "st")
        #expect(
            url.absoluteString
                == "https://accounts.google.com/o/oauth2/v2/auth?client_id=123-abc.apps.googleusercontent.com&response_type=code"
                + "&redirect_uri=com.googleusercontent.apps.123-abc:/oauth2redirect"
                + "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=st"
                + "&scope=https://www.googleapis.com/auth/drive.file&access_type=offline&prompt=consent")
        #expect(CloudProvider.googleDrive.callbackScheme(clientID: "123-abc.apps.googleusercontent.com") == "com.googleusercontent.apps.123-abc")
        #expect(CloudProvider.googleDrive.redirectURI(clientID: "123-abc") == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    @Test func buildsTheExactMicrosoftAuthorizeURLForPersonalAndWorkAccounts() {
        let url = OAuthRequests.authorizationURL(provider: .oneDrive, clientID: "00000000-1111-2222-3333-444444444444", pkce: pkce, state: "st")
        #expect(
            url.absoluteString
                == "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=00000000-1111-2222-3333-444444444444&response_type=code"
                + "&redirect_uri=ishare-oauth://onedrive"
                + "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=st"
                + "&scope=Files.ReadWrite%20User.Read%20offline_access&prompt=select_account")
        #expect(CloudProvider.oneDrive.tokenEndpoint.absoluteString == "https://login.microsoftonline.com/common/oauth2/v2.0/token")
    }

    @Test func exchangesCodesWithoutAClientSecret() throws {
        for provider in CloudProvider.allCases {
            let request = OAuthRequests.tokenRequest(provider: provider, clientID: "id", code: "c", verifier: "v")
            let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
            #expect(!body.contains("client_secret"))
            #expect(body.contains("code_verifier=v"))
            #expect(request.url == provider.tokenEndpoint)
        }
    }

    @Test func listsProvidersWithABuiltInClientIDDirectlyInTheCreateMenu() {
        let groups = CloudProvider.createMenuGroups { $0 == .googleDrive }
        #expect(groups.builtIn == [.googleDrive])
        #expect(groups.ownApp == [.dropbox, .oneDrive])
        #expect(CloudProvider.createMenuGroups { _ in true }.ownApp.isEmpty)
        let live = CloudProvider.createMenuGroups()
        #expect(live.builtIn == CloudProvider.allCases.filter(\.hasBuiltInClientID))
    }

    @Test func expandsTheClientIDsIntoTheBuiltInfoPlist() throws {
        let info = try #require(Bundle.main.infoDictionary)
        for key in ["ISHAREDropboxClientID", "ISHAREGoogleClientID", "ISHAREOneDriveClientID"] {
            let value = try #require(info[key] as? String, "\(key) is missing from the app's Info.plist")
            #expect(!value.hasPrefix("$("), "\(key) wasn't expanded from Config.xcconfig")
        }
    }

    @Test func everyInfoPlistAndConfigurationReadsTheClientIDsFromConfig() throws {
        let config = try String(contentsOf: Fixtures.url("Config.xcconfig"), encoding: .utf8)
        let variables = ["DROPBOX_CLIENT_ID": "ISHAREDropboxClientID", "GOOGLE_CLIENT_ID": "ISHAREGoogleClientID", "ONEDRIVE_CLIENT_ID": "ISHAREOneDriveClientID"]
        for plist in ["ishare/Info.plist", "ishare/Info-GitHub.plist"] {
            let object = try PropertyListSerialization.propertyList(from: Fixtures.data(plist), format: nil) as? [String: Any]
            for (variable, key) in variables {
                #expect(object?[key] as? String == "$(\(variable))", "\(plist) doesn't read \(key) from \(variable)")
                #expect(config.contains("\(variable) ="), "Config.xcconfig doesn't declare \(variable)")
            }
        }
        let project = try String(contentsOf: Fixtures.url("project.yml"), encoding: .utf8)
        #expect(project.contains("Debug: Config.xcconfig"))
        #expect(project.contains("Release: Config.xcconfig"))
    }
}
