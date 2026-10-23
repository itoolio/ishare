import Defaults
import Foundation
import Security
import Testing
@testable import ishare

final class FakeKeychain: KeychainClient, @unchecked Sendable {
    struct Item {
        var data: Data
        var attributes: [String: Any]
    }

    var legacy: [String: Item] = [:]
    var protected: [String: Item] = [:]
    var rejectsDataProtection = false
    var queries: [[String: Any]] = []
    private let lock = NSLock()

    private static func account(_ query: [String: Any]) -> String {
        query[kSecAttrAccount as String] as? String ?? ""
    }

    private static func usesDataProtection(_ query: [String: Any]) -> Bool {
        query[kSecUseDataProtectionKeychain as String] as? Bool == true
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.withLock {
            queries.append(query)
            if Self.usesDataProtection(query) {
                if rejectsDataProtection { return (errSecMissingEntitlement, nil) }
                return protected[Self.account(query)].map { (errSecSuccess, $0.data) } ?? (errSecItemNotFound, nil)
            }
            return legacy[Self.account(query)].map { (errSecSuccess, $0.data) } ?? (errSecItemNotFound, nil)
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            let account = Self.account(attributes)
            let item = Item(data: attributes[kSecValueData as String] as? Data ?? Data(), attributes: attributes)
            if Self.usesDataProtection(attributes) {
                if rejectsDataProtection { return errSecMissingEntitlement }
                guard protected[account] == nil else { return errSecDuplicateItem }
                protected[account] = item
            } else {
                guard legacy[account] == nil else { return errSecDuplicateItem }
                legacy[account] = item
            }
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            let account = Self.account(query)
            let data = attributes[kSecValueData as String] as? Data ?? Data()
            if Self.usesDataProtection(query) {
                if rejectsDataProtection { return errSecMissingEntitlement }
                guard protected[account] != nil else { return errSecItemNotFound }
                protected[account]?.data = data
            } else {
                guard legacy[account] != nil else { return errSecItemNotFound }
                legacy[account]?.data = data
            }
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            let account = Self.account(query)
            if Self.usesDataProtection(query) {
                return protected.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
            }
            return legacy.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}

struct KeychainQueryTests {
    let group = "L988J7YMK5.dev.adrian.ishare.shared"

    @Test func readQueriesMatchSynchronizableAnyInTheSharedGroup() {
        let query = KeychainQueries.reading(KeychainQueries.synchronized(service: "svc", account: "acc", accessGroup: group))
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "svc")
        #expect(query[kSecAttrAccount as String] as? String == "acc")
        #expect(query[kSecAttrSynchronizable as String] as? String == kSecAttrSynchronizableAny as String)
        #expect(query[kSecAttrAccessGroup as String] as? String == group)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
    }

    @Test func newItemsAreSynchronizableAndAccessibleAfterFirstUnlock() {
        let item = KeychainQueries.synchronizedItem(service: "svc", account: "acc", accessGroup: group, data: Data("s".utf8))
        #expect(item[kSecAttrSynchronizable as String] as? Bool == true)
        #expect(item[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(item[kSecAttrAccessGroup as String] as? String == group)
        #expect(item[kSecValueData as String] as? Data == Data("s".utf8))
        #expect(item[kSecAttrLabel as String] as? String == KeychainQueries.label)
    }

    @Test func omitsTheAccessGroupWhenTheAppIsNotEntitled() {
        let query = KeychainQueries.synchronized(service: "svc", account: "acc", accessGroup: nil)
        #expect(query[kSecAttrAccessGroup as String] == nil)
        let legacy = KeychainQueries.legacy(service: "svc", account: "acc")
        #expect(legacy[kSecAttrSynchronizable as String] == nil)
        #expect(legacy[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test func resolvesTheSharedGroupFromEntitlements() {
        #expect(SharedKeychainGroup.resolve(entitledGroups: ["ABC.other", group]) == group)
        #expect(SharedKeychainGroup.resolve(entitledGroups: ["ABC.dev.adrian.ishare.sharedx"]) == nil)
        #expect(SharedKeychainGroup.resolve(entitledGroups: []) == nil)
    }
}

struct KeychainBackendTests {
    func backend(_ keychain: FakeKeychain) -> KeychainSecretBackend {
        KeychainSecretBackend(service: "svc", accessGroup: "T.dev.adrian.ishare.shared", client: keychain)
    }

    func legacyItem(_ secret: String) -> FakeKeychain.Item {
        FakeKeychain.Item(data: Data(secret.utf8), attributes: [:])
    }

    @Test func writesSynchronizableItems() throws {
        let keychain = FakeKeychain()
        try backend(keychain).write("secret", account: "a")
        #expect(keychain.protected["a"]?.data == Data("secret".utf8))
        #expect(keychain.protected["a"]?.attributes[kSecAttrSynchronizable as String] as? Bool == true)
        #expect(keychain.legacy.isEmpty)
        try backend(keychain).write("changed", account: "a")
        #expect(backend(keychain).read(account: "a") == "changed")
    }

    @Test func readingALegacyItemMigratesItOnce() {
        let keychain = FakeKeychain()
        keychain.legacy["a"] = legacyItem("old")
        #expect(backend(keychain).read(account: "a") == "old")
        #expect(keychain.legacy["a"] == nil)
        #expect(keychain.protected["a"]?.data == Data("old".utf8))
        #expect(backend(keychain).read(account: "a") == "old")
        #expect(backend(keychain).makeSynchronizable(account: "a") == false)
    }

    @Test func makeSynchronizableIsIdempotent() {
        let keychain = FakeKeychain()
        keychain.legacy["a"] = legacyItem("old")
        #expect(backend(keychain).makeSynchronizable(account: "a"))
        #expect(backend(keychain).makeSynchronizable(account: "a") == false)
        #expect(backend(keychain).makeSynchronizable(account: "missing") == false)
        #expect(keychain.protected.count == 1)
        #expect(keychain.legacy.isEmpty)
    }

    @Test func fallsBackToTheLegacyKeychainWithoutTheEntitlement() throws {
        let keychain = FakeKeychain()
        keychain.rejectsDataProtection = true
        try backend(keychain).write("local", account: "a")
        #expect(keychain.legacy["a"]?.data == Data("local".utf8))
        #expect(backend(keychain).read(account: "a") == "local")
        #expect(keychain.legacy["a"] != nil)
        #expect(backend(keychain).makeSynchronizable(account: "a") == false)
    }

    @Test func deleteRemovesBothCopies() {
        let keychain = FakeKeychain()
        keychain.legacy["a"] = legacyItem("x")
        keychain.protected["a"] = legacyItem("y")
        backend(keychain).delete(account: "a")
        #expect(keychain.legacy.isEmpty)
        #expect(keychain.protected.isEmpty)
    }
}

@MainActor
struct SynchronizableMigrationTests {
    init() {
        TestSecrets.install()
    }

    @Test func migrationPromotesLocalOnlySecretsAndBumpsTheVersion() throws {
        let suite = "dev.adrian.ishare.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3, forKey: Migrations.versionKey)
        let key = Defaults.Key<Set<CustomUploader>?>("savedCustomUploaders", suite: defaults)
        let configuration = S3Configuration(endpoint: "https://s3.example.com", region: "r", bucket: "b", accessKeyId: "a", secretAccessKey: S3SecretStore.placeholder)
        let uploader = CustomUploader.s3(name: "s3", configuration: configuration)
        Defaults[key] = [uploader]
        TestSecrets.backend.storeLocalOnly("secret", account: uploader.id.uuidString)
        Migrations.run(defaults: defaults)
        #expect(TestSecrets.backend.isSynchronizable(account: uploader.id.uuidString))
        #expect(defaults.integer(forKey: Migrations.versionKey) == Migrations.currentVersion)
        #expect(S3SecretStore.makeSynchronizable([uploader]).isEmpty)
        #expect(S3SecretStore.secret(for: uploader) == "secret")
    }

    @Test func missingSecretMentionsICloudKeychain() {
        let message = S3SecretError.missingSecret("aws").errorDescription ?? ""
        #expect(message.contains("aws"))
        #expect(message.contains("iCloud Keychain"))
    }
}

struct URLShortenerRequestTests {
    let long = URL(string: "https://cdn.example.com/a.png?x=1&y=2")!

    @Test func presetsTargetIsGdAndVGd() throws {
        let isgd = try URLShortenerRequest.make(#require(URLShortenerConfiguration(kind: .isgd).request), for: URL(string: "https://e.com/a?b=c")!)
        #expect(isgd.url?.absoluteString == "https://is.gd/create.php?format=simple&url=https%3A%2F%2Fe.com%2Fa%3Fb%3Dc")
        #expect(isgd.httpMethod == "GET")
        let vgd = try #require(URLShortenerConfiguration(kind: .vgd).request)
        #expect(vgd.requestURL.hasPrefix("https://v.gd/"))
        #expect(URLShortenerConfiguration.none.request == nil)
    }

    @Test func fillsCustomTemplatesInURLHeadersAndBody() throws {
        let shortener = CustomShortener(
            requestURL: "https://s.example.com/new", method: .post, headers: ["X-Long": "{{url}}"],
            body: #"{"long": "{{url}}"}"#, responseTemplate: "{{data.short}}"
        )
        let request = try URLShortenerRequest.make(shortener, for: URL(string: "https://e.com/a.png")!)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Long") == "https://e.com/a.png")
        #expect(request.httpBody == Data(#"{"long": "https://e.com/a.png"}"#.utf8))
    }

    @Test func rejectsUnknownPlaceholdersAndNonHTTPURLs() {
        #expect(throws: URLShortenerError.invalidRequest("nope")) {
            try URLShortenerRequest.make(CustomShortener(requestURL: "https://s.example.com/{{nope}}"), for: long)
        }
        #expect(throws: URLShortenerError.self) {
            try URLShortenerRequest.make(CustomShortener(requestURL: "ftp://s.example.com/{{url_encoded}}"), for: long)
        }
    }

    @Test func parsesPlainAndJSONResponses() throws {
        #expect(try URLShortenerRequest.shortURL(from: Data("https://is.gd/abc\n".utf8), template: "{{response}}").absoluteString == "https://is.gd/abc")
        #expect(try URLShortenerRequest.shortURL(from: Data(#"{"data":{"short":"https://s.io/x"}}"#.utf8), template: "{{data.short}}").absoluteString == "https://s.io/x")
        #expect(throws: URLShortenerError.self) {
            try URLShortenerRequest.shortURL(from: Data("Error: Please enter a valid URL".utf8), template: "{{response}}")
        }
        #expect(throws: URLShortenerError.invalidResponse("data.short")) {
            try URLShortenerRequest.shortURL(from: Data("{}".utf8), template: "{{data.short}}")
        }
    }

    @Test func configurationsRoundTrip() throws {
        let configuration = URLShortenerConfiguration(kind: .custom, custom: CustomShortener(requestURL: "https://a.b/{{url}}", headers: ["A": "b"]))
        let decoded = try JSONDecoder().decode(URLShortenerConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(decoded == configuration)
    }
}

struct UploadPresetModelTests {
    @Test func historyItemsWithoutShortURLsStillDecode() throws {
        let item = try JSONDecoder().decode(HistoryItem.self, from: Data(#"{"fileUrl":"https://e.com/a.png"}"#.utf8))
        #expect(item.shortUrl == nil)
        #expect(item.preferredURL?.absoluteString == "https://e.com/a.png")
        let short = HistoryItem(fileUrl: "https://e.com/a.png", shortUrl: "https://is.gd/x")
        #expect(short.preferredURL?.absoluteString == "https://is.gd/x")
        #expect(try JSONDecoder().decode(HistoryItem.self, from: JSONEncoder().encode(short)) == short)
    }

    @Test func presetsRoundTripAndTolerateMissingFields() throws {
        let preset = UploadPreset(
            name: "Work S3", destination: .custom(UUID()), additionalDestinations: [.builtIn(.IMGUR)],
            shortener: URLShortenerConfiguration(kind: .isgd), stepOverrides: [.copyToClipboard: false, .upload: true]
        )
        let decoded = try JSONDecoder().decode(UploadPreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded == preset)
        #expect(decoded.override(for: .copyToClipboard) == false)
        #expect(decoded.override(for: .mail) == nil)
        let sparse = try JSONDecoder().decode(UploadPreset.self, from: Data(#"{"name":"Old","stepOverrides":{"retired":true}}"#.utf8))
        #expect(sparse.name == "Old")
        #expect(sparse.destination == .builtIn(.IMGUR))
        #expect(sparse.additionalDestinations.isEmpty)
    }

    @Test func shortcutNamesAreDerivedFromThePresetID() throws {
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(UploadPresets.shortcutName(for: id).rawValue == "preset-6F9619FF-8B86-D011-B42D-00C04FC964FF")
    }

    @MainActor @Test func overridesWinOverAfterCaptureSettings() {
        let previousCopy = Defaults[.copyToClipboard]
        let previousUpload = Defaults[.uploadMedia]
        let previousSave = Defaults[.saveToDisk]
        defer {
            Defaults[.copyToClipboard] = previousCopy
            Defaults[.uploadMedia] = previousUpload
            Defaults[.saveToDisk] = previousSave
        }
        Defaults[.copyToClipboard] = true
        Defaults[.uploadMedia] = false
        Defaults[.saveToDisk] = true
        var preset = UploadPreset(name: "p", destination: .builtIn(.IMGUR))
        preset.setOverride(false, for: .copyToClipboard)
        preset.setOverride(false, for: .saveToDisk)
        preset.setOverride(true, for: .openInFinder)
        let options = CaptureOptions(preset: preset)
        #expect(options.isEnabled(.copyToClipboard) == false)
        #expect(options.isEnabled(.upload))
        #expect(options.isEnabled(.saveToDisk) == false)
        #expect(options.isEnabled(.openInFinder) == false)
        #expect(AfterCaptureStep.upload.runs(for: .image, options: options))
        #expect(CaptureOptions.standard.isEnabled(.copyToClipboard))
        #expect(CaptureOptions.standard.isEnabled(.upload) == false)
        preset.setOverride(false, for: .upload)
        #expect(AfterCaptureStep.upload.runs(for: .image, options: CaptureOptions(preset: preset)) == false)
    }

    @MainActor @Test func storeSavesMovesAndDeletes() {
        let previous = Defaults[.uploadPresets]
        defer { Defaults[.uploadPresets] = previous }
        Defaults[.uploadPresets] = []
        let first = UploadPreset(name: "A", destination: .builtIn(.IMGUR))
        let second = UploadPreset(name: "B", destination: .builtIn(.IMGUR))
        UploadPresets.save(first)
        UploadPresets.save(second)
        var renamed = first
        renamed.name = "A2"
        UploadPresets.save(renamed)
        #expect(UploadPresets.all.map(\.name) == ["A2", "B"])
        UploadPresets.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(UploadPresets.all.map(\.name) == ["B", "A2"])
        UploadPresets.delete(second)
        #expect(UploadPresets.all.map(\.id) == [first.id])
        #expect(UploadPresets.preset(id: first.id)?.name == "A2")
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct ShortenerPipelineTests {
        let spy = UploadEnvironmentSpy()

        init() {
            UploadService.session = StubURLProtocol.makeSession()
            UploadCoordinator.environment = spy
            StubURLProtocol.reset { request in
                switch request.url.host() {
                case "primary.example.com":
                    StubResponse(body: Data(#"{"url": "https://cdn.primary.example.com/a.png"}"#.utf8))
                case "mirror.example.com":
                    StubResponse(body: Data(#"{"url": "https://cdn.mirror.example.com/a.png"}"#.utf8))
                case "is.gd":
                    StubResponse(headers: ["Content-Type": "text/plain"], body: Data("https://is.gd/short".utf8))
                case "broken.example.com":
                    StubResponse(status: 500, body: Data("nope".utf8))
                default:
                    StubResponse(status: 404)
                }
            }
        }

        func finish() {
            UploadCoordinator.environment = LiveUploadEnvironment()
        }

        @Test func shortensTheDeliveredURLAndStoresBoth() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let primary = UploadTarget.custom(TestUploaders.http(name: "primary", host: "primary.example.com"))
            let mirror = UploadTarget.custom(TestUploaders.http(name: "mirror", host: "mirror.example.com"))
            let result = await UploadCoordinator.upload(
                fileURL: file, primary: primary, additional: [mirror], shortener: URLShortenerConfiguration(kind: .isgd), localFileURL: nil
            )
            #expect(try result.get().shortURL?.absoluteString == "https://is.gd/short")
            #expect(spy.delivered.map(\.absoluteString) == ["https://is.gd/short"])
            #expect(spy.history.map(\.fileUrl) == ["https://cdn.primary.example.com/a.png", "https://cdn.mirror.example.com/a.png"])
            #expect(spy.history.map(\.shortUrl) == ["https://is.gd/short", nil])
            let shortenRequest = try #require(StubURLProtocol.captured.first { $0.url.host() == "is.gd" })
            #expect(shortenRequest.url.query()?.contains("url=https%3A%2F%2Fcdn.primary.example.com%2Fa.png") == true)
        }

        @Test func fallsBackToTheLongURLWhenShorteningFails() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let primary = UploadTarget.custom(TestUploaders.http(name: "primary", host: "primary.example.com"))
            let shortener = URLShortenerConfiguration(kind: .custom, custom: CustomShortener(requestURL: "https://broken.example.com/?u={{url_encoded}}"))
            let result = await UploadCoordinator.upload(fileURL: file, primary: primary, additional: [], shortener: shortener, localFileURL: nil)
            #expect(try result.get().shortURL == nil)
            #expect(spy.delivered.map(\.absoluteString) == ["https://cdn.primary.example.com/a.png"])
            #expect(spy.history.first?.shortUrl == nil)
            #expect(spy.notifications.isEmpty)
        }

        @Test func noShortenerMeansNoExtraRequest() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let primary = UploadTarget.custom(TestUploaders.http(name: "primary", host: "primary.example.com"))
            _ = await UploadCoordinator.upload(fileURL: file, primary: primary, additional: [], shortener: .none, localFileURL: nil)
            #expect(StubURLProtocol.captured.count == 1)
            #expect(spy.delivered.map(\.absoluteString) == ["https://cdn.primary.example.com/a.png"])
        }

        @Test func presetsChooseDestinationsAndShortener() async throws {
            defer { finish() }
            let previous = Defaults[.savedCustomUploaders]
            defer { Defaults[.savedCustomUploaders] = previous }
            let primary = TestUploaders.http(name: "primary", host: "primary.example.com")
            let mirror = TestUploaders.http(name: "mirror", host: "mirror.example.com")
            Defaults[.savedCustomUploaders] = [primary, mirror]
            let preset = UploadPreset(
                name: "Work", destination: .custom(primary.id), additionalDestinations: [.custom(primary.id), .custom(mirror.id)],
                shortener: URLShortenerConfiguration(kind: .isgd)
            )
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let result = await UploadCoordinator.upload(fileURL: file, preset: preset)
            #expect(try result.get().url.absoluteString == "https://cdn.primary.example.com/a.png")
            #expect(spy.history.map(\.fileUrl) == ["https://cdn.primary.example.com/a.png", "https://cdn.mirror.example.com/a.png"])
            #expect(spy.delivered.map(\.absoluteString) == ["https://is.gd/short"])
        }

        @Test func presetsWithAMissingUploaderFailCleanly() async {
            defer { finish() }
            let preset = UploadPreset(name: "Gone", destination: .custom(UUID()))
            let result = await UploadCoordinator.upload(fileURL: URL(fileURLWithPath: "/tmp/none.png"), preset: preset)
            #expect((try? result.get()) == nil)
            #expect(spy.notifications == ["No uploader is selected".localized()])
            #expect(StubURLProtocol.captured.isEmpty)
        }
    }
}
