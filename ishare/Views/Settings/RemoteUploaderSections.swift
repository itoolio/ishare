import AppKit
import ishareCore
import SwiftUI

struct WebDAVDraft: Equatable {
    var url = ""
    var username = ""
    var password = ""
    var authentication: WebDAVAuthentication = .basic
    var pathTemplate = RemotePath.defaultTemplate
    var createDirectories = true
    var publicURL = ""

    init() {}

    init(uploader: CustomUploader) {
        guard let configuration = uploader.webdav else { return }
        url = configuration.url
        username = configuration.username ?? ""
        password = UploaderSecrets.revealed(configuration.password, .password, for: uploader.id) ?? ""
        authentication = configuration.authenticationMethod
        pathTemplate = configuration.pathTemplate ?? ""
        createDirectories = configuration.createsDirectories
        publicURL = configuration.publicURL ?? ""
    }

    var configuration: WebDAVConfiguration {
        WebDAVConfiguration(
            url: url.trimmingCharacters(in: .whitespaces), username: username.nilIfEmpty, password: password.nilIfEmpty,
            authentication: authentication == .basic ? nil : authentication, pathTemplate: pathTemplate.nilIfEmpty,
            createDirectories: createDirectories ? nil : false, publicURL: publicURL.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )
    }
}

struct WebDAVSections: View {
    @Binding var draft: WebDAVDraft

    var body: some View {
        Section("Server".localized()) {
            TextField("WebDAV URL".localized(), text: $draft.url, prompt: Text("https://cloud.example.com/remote.php/dav/files/me"))
            TextField("Username".localized(), text: $draft.username)
            SecureField("Password".localized(), text: $draft.password)
            Picker("Authentication".localized(), selection: $draft.authentication) {
                Text("Basic").tag(WebDAVAuthentication.basic)
                Text("Digest").tag(WebDAVAuthentication.digest)
            }
        }
        RemotePathSection(pathTemplate: $draft.pathTemplate, createDirectories: $draft.createDirectories, publicURL: $draft.publicURL, publicURLRequired: false)
    }
}

struct RemotePathSection: View {
    @Binding var pathTemplate: String
    @Binding var createDirectories: Bool
    @Binding var publicURL: String
    let publicURLRequired: Bool

    var body: some View {
        Section("Files".localized()) {
            TextField("Path template".localized(), text: $pathTemplate, prompt: Text(RemotePath.defaultTemplate))
            Toggle("Create missing folders".localized(), isOn: $createDirectories)
            TextField("Public URL".localized(), text: $publicURL, prompt: Text("https://files.example.com/{{path}}"))
            Text(
                "Path placeholders: {{filename}}, {{name}}, {{ext}}, {{uuid}}, {{random}}, {{timestamp}}, {{date}}, {{year}}, {{month}}, {{day}}. Public URL placeholders: {{path}}, {{filename}}, {{directory}}."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            if publicURLRequired, publicURL.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Without a public URL the upload is saved to history but no link is copied.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SFTPDraft: Equatable {
    var host = ""
    var port = SFTPConfiguration.defaultPort
    var username = ""
    var usesPrivateKey = false
    var password = ""
    var privateKey = ""
    var passphrase = ""
    var directory = ""
    var pathTemplate = RemotePath.defaultTemplate
    var createDirectories = true
    var publicURL = ""
    var hostKeyFingerprint = ""

    init() {}

    init(uploader: CustomUploader) {
        guard let configuration = uploader.sftp else { return }
        host = configuration.host
        port = configuration.resolvedPort
        username = configuration.username
        password = UploaderSecrets.revealed(configuration.password, .password, for: uploader.id) ?? ""
        privateKey = UploaderSecrets.revealed(configuration.privateKey, .privateKey, for: uploader.id) ?? ""
        passphrase = UploaderSecrets.revealed(configuration.passphrase, .passphrase, for: uploader.id) ?? ""
        usesPrivateKey = !privateKey.isEmpty
        directory = configuration.directory ?? ""
        pathTemplate = configuration.pathTemplate ?? ""
        createDirectories = configuration.createsDirectories
        publicURL = configuration.publicURL ?? ""
        hostKeyFingerprint = configuration.hostKeyFingerprint ?? ""
    }

    var configuration: SFTPConfiguration {
        SFTPConfiguration(
            host: host.trimmingCharacters(in: .whitespaces), port: port == SFTPConfiguration.defaultPort ? nil : port,
            username: username.trimmingCharacters(in: .whitespaces), password: usesPrivateKey ? nil : password.nilIfEmpty,
            privateKey: usesPrivateKey ? privateKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil,
            passphrase: usesPrivateKey ? passphrase.nilIfEmpty : nil, directory: directory.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            pathTemplate: pathTemplate.nilIfEmpty, createDirectories: createDirectories ? nil : false,
            publicURL: publicURL.trimmingCharacters(in: .whitespaces).nilIfEmpty, hostKeyFingerprint: hostKeyFingerprint.nilIfEmpty
        )
    }
}

struct SFTPSections: View {
    @Binding var draft: SFTPDraft
    @State private var isChecking = false
    @State private var checkError: String?

    var body: some View {
        Section("Server".localized()) {
            TextField("Host".localized(), text: $draft.host, prompt: Text("files.example.com"))
            TextField("Port".localized(), value: $draft.port, format: .number.grouping(.never))
            TextField("Username".localized(), text: $draft.username)
            Picker("Sign in with".localized(), selection: $draft.usesPrivateKey) {
                Text("Password".localized()).tag(false)
                Text("Private key".localized()).tag(true)
            }
            .pickerStyle(.segmented)
            if draft.usesPrivateKey {
                TextEditor(text: $draft.privateKey)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .overlay(alignment: .topLeading) {
                        if draft.privateKey.isEmpty {
                            Text("-----BEGIN OPENSSH PRIVATE KEY-----")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    SecureField("Key passphrase".localized(), text: $draft.passphrase)
                    Button("Choose Key File…".localized(), action: chooseKey)
                }
                Text("Ed25519 and RSA keys in OpenSSH format are supported. The key is stored in your Keychain.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                SecureField("Password".localized(), text: $draft.password)
            }
        }
        Section("Host Key".localized()) {
            LabeledContent("Trusted fingerprint".localized()) {
                Text(draft.hostKeyFingerprint.isEmpty ? "Trusted on first connection".localized() : draft.hostKeyFingerprint)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(draft.hostKeyFingerprint.isEmpty ? .secondary : .primary)
            }
            HStack {
                Button("Check Host Key".localized(), action: checkHostKey)
                    .disabled(draft.configuration.trimmedHost.isEmpty || isChecking)
                if !draft.hostKeyFingerprint.isEmpty {
                    Button("Forget".localized()) { draft.hostKeyFingerprint = "" }
                }
                if isChecking {
                    ProgressView().controlSize(.small)
                }
            }
            if let checkError {
                Label(checkError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            Text(
                "ishare remembers the server's host key the first time it connects and refuses to upload if the key changes. Compare the fingerprint with ssh-keygen -lf on the server."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Section("Remote Folder".localized()) {
            TextField("Folder".localized(), text: $draft.directory, prompt: Text("/var/www/uploads"))
        }
        RemotePathSection(pathTemplate: $draft.pathTemplate, createDirectories: $draft.createDirectories, publicURL: $draft.publicURL, publicURLRequired: true)
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh", directoryHint: .isDirectory)
        Task { @MainActor in
            guard await panel.beginAsyncModal() == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let key = try? String(contentsOf: url, encoding: .utf8) {
                draft.privateKey = key
            }
        }
    }

    private func checkHostKey() {
        isChecking = true
        checkError = nil
        var configuration = draft.configuration
        configuration.hostKeyFingerprint = nil
        Task { @MainActor in
            defer { isChecking = false }
            do {
                draft.hostKeyFingerprint = try await SFTPTransport.probe(configuration)
            } catch let error as SFTPProbeError {
                draft.hostKeyFingerprint = error.fingerprint
                checkError = error.localizedDescription
            } catch {
                checkError = error.localizedDescription
            }
        }
    }
}

struct CloudDraft: Equatable {
    var folder = CloudStorageConfiguration.defaultFolder
    var pathTemplate = CloudStorageConfiguration.defaultPathTemplate
    var clientID = ""
    var account = ""
    var directLink = false

    init() {}

    init(uploader: CustomUploader) {
        guard let configuration = uploader.cloud else { return }
        folder = configuration.folder ?? CloudStorageConfiguration.defaultFolder
        pathTemplate = configuration.pathTemplate ?? CloudStorageConfiguration.defaultPathTemplate
        clientID = configuration.clientID ?? ""
        account = configuration.account ?? ""
        directLink = configuration.directLink ?? false
    }

    var configuration: CloudStorageConfiguration {
        CloudStorageConfiguration(
            folder: folder.trimmingCharacters(in: .whitespaces), pathTemplate: pathTemplate == CloudStorageConfiguration.defaultPathTemplate ? nil : pathTemplate.nilIfEmpty,
            clientID: clientID.trimmingCharacters(in: .whitespaces).nilIfEmpty, account: account.nilIfEmpty, directLink: directLink ? true : nil
        )
    }
}

struct CloudSections: View {
    let provider: CloudProvider
    let uploaderID: UUID
    @Binding var draft: CloudDraft
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var isSignedIn = false

    var body: some View {
        Section("Account".localized()) {
            LabeledContent(provider.title.localized()) {
                HStack {
                    if isSignedIn {
                        Text(draft.account.isEmpty ? "Signed in".localized() : draft.account)
                            .foregroundStyle(.secondary)
                        Button("Sign Out".localized(), action: signOut)
                    } else {
                        Button(String(format: "Sign in to %@".localized(), provider.title.localized()), action: signIn)
                            .disabled(isSigningIn || !hasClientID)
                    }
                    if isSigningIn {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .onAppear(perform: refresh)
            if let signInError {
                Label(signInError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            Text("ishare signs in through your browser and keeps the access and refresh tokens in your Keychain.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section("Files".localized()) {
            TextField("Folder".localized(), text: $draft.folder, prompt: Text(CloudStorageConfiguration.defaultFolder))
            TextField("File name template".localized(), text: $draft.pathTemplate, prompt: Text(CloudStorageConfiguration.defaultPathTemplate))
            if provider == .dropbox {
                Toggle("Direct link to the file".localized(), isOn: $draft.directLink)
            }
            Text(linkDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if provider.hasBuiltInClientID {
            Section {
                DisclosureGroup("Use your own app".localized()) {
                    clientIDField
                }
            }
        } else {
            Section("Your App".localized()) {
                clientIDField
            }
        }
    }

    private var clientIDField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Client ID".localized(), text: $draft.clientID)
                .font(.system(.body, design: .monospaced))
            Text(String(format: "Register an app with %@ and add the redirect URI %@.".localized(), provider.title.localized(), redirectURI))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var hasClientID: Bool {
        (try? OAuthSession.clientID(provider: provider, configuration: draft.configuration)) != nil
    }

    private var redirectURI: String {
        let clientID = (try? OAuthSession.clientID(provider: provider, configuration: draft.configuration)) ?? "<client id>"
        return provider.redirectURI(clientID: clientID)
    }

    private var linkDescription: String {
        switch provider {
        case .dropbox: "ishare creates a public shared link for each upload.".localized()
        case .googleDrive: "ishare shares each upload with anyone who has the link. It can only see files it uploaded itself.".localized()
        case .oneDrive: "ishare creates a view-only sharing link for each upload.".localized()
        }
    }

    private func refresh() {
        isSignedIn = OAuthTokenStore.token(for: uploaderID) != nil
    }

    private func signIn() {
        isSigningIn = true
        signInError = nil
        let configuration = draft.configuration
        Task { @MainActor in
            defer { isSigningIn = false }
            do {
                let token = try await OAuthSignIn.signIn(provider: provider, configuration: configuration, uploaderID: uploaderID)
                draft.account = token.account ?? ""
                isSignedIn = true
            } catch OAuthError.cancelled {
                refresh()
            } catch {
                signInError = error.localizedDescription
                refresh()
            }
        }
    }

    private func signOut() {
        OAuthSignIn.signOut(uploaderID: uploaderID)
        draft.account = ""
        isSignedIn = false
    }
}

struct GitHubDraft: Equatable {
    var repository = ""
    var branch = ""
    var pathTemplate = GitHubConfiguration.defaultPathTemplate
    var linkStyle: GitHubLinkStyle = .raw
    var token = ""
    var textAsGist = true
    var publicGists = false

    init() {}

    init(uploader: CustomUploader) {
        guard let configuration = uploader.github else { return }
        repository = configuration.repository
        branch = configuration.branch ?? ""
        pathTemplate = configuration.pathTemplate ?? GitHubConfiguration.defaultPathTemplate
        linkStyle = configuration.style
        token = UploaderSecrets.revealed(configuration.token, .accessToken, for: uploader.id) ?? ""
        textAsGist = configuration.sendsTextToGist
        publicGists = configuration.publicGists ?? false
    }

    var configuration: GitHubConfiguration {
        GitHubConfiguration(
            repository: repository.trimmingCharacters(in: .whitespaces), branch: branch.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            pathTemplate: pathTemplate == GitHubConfiguration.defaultPathTemplate ? nil : pathTemplate.nilIfEmpty,
            linkStyle: linkStyle == .raw ? nil : linkStyle, token: token.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            textAsGist: textAsGist ? nil : false, publicGists: publicGists ? true : nil
        )
    }
}

struct GitHubSections: View {
    @Binding var draft: GitHubDraft
    @State private var deviceCode: GitHubDeviceCode?
    @State private var deviceError: String?
    @State private var deviceTask: Task<Void, Never>?

    var body: some View {
        Section("Repository".localized()) {
            TextField("Repository".localized(), text: $draft.repository, prompt: Text("owner/screenshots"))
            TextField("Branch".localized(), text: $draft.branch, prompt: Text("main"))
            TextField("Path template".localized(), text: $draft.pathTemplate, prompt: Text(GitHubConfiguration.defaultPathTemplate))
            Picker("Link".localized(), selection: $draft.linkStyle) {
                ForEach(GitHubLinkStyle.allCases, id: \.self) { style in
                    Text(style.titleKey.localized()).tag(style)
                }
            }
            Text("Raw links only work for public repositories. Markdown copies an image or link snippet instead of the bare URL.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section("Text Snippets".localized()) {
            Toggle("Upload text as a Gist".localized(), isOn: $draft.textAsGist)
            if draft.textAsGist {
                Toggle("Public Gists".localized(), isOn: $draft.publicGists)
            }
        }
        Section("Access".localized()) {
            SecureField("Personal access token".localized(), text: $draft.token, prompt: Text("github_pat_…"))
            Text(String(format: "Create a fine-grained token limited to the upload repository with these permissions: %@.".localized(), GitHubConfiguration.tokenPermissions))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Create Token on GitHub…".localized()) {
                NSWorkspace.shared.open(URL(string: "https://github.com/settings/personal-access-tokens/new")!)
            }
            if let clientID = GitHubAPI.builtInClientID {
                deviceFlowRow(clientID: clientID)
            }
        }
        .onDisappear { deviceTask?.cancel() }
    }

    @ViewBuilder
    private func deviceFlowRow(clientID: String) -> some View {
        if let deviceCode {
            LabeledContent("Enter this code on GitHub".localized()) {
                HStack {
                    Text(deviceCode.userCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    ProgressView().controlSize(.small)
                    Button("Cancel".localized()) {
                        deviceTask?.cancel()
                        self.deviceCode = nil
                    }
                }
            }
        } else {
            Button("Sign in with GitHub".localized()) { startDeviceFlow(clientID: clientID) }
        }
        if let deviceError {
            Label(deviceError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.footnote)
        }
    }

    private func startDeviceFlow(clientID: String) {
        deviceError = nil
        deviceTask = Task { @MainActor in
            do {
                let code = try await GitHubDeviceFlow.start(clientID: clientID)
                deviceCode = code
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationURL)
                draft.token = try await GitHubDeviceFlow.waitForToken(clientID: clientID, code: code)
            } catch is CancellationError {
            } catch {
                deviceError = error.localizedDescription
            }
            deviceCode = nil
        }
    }
}
