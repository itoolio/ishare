import AppKit
import ishareCore
import SwiftUI

struct FolderDraft: Equatable {
    var path = ""
    var bookmark: Data?
    var subfolderTemplate = ""
    var publicURL = ""

    init() {}

    init(destination: FolderDestination?, bookmark: Data?) {
        path = destination?.path ?? ""
        self.bookmark = bookmark
        subfolderTemplate = destination?.subfolderTemplate ?? ""
        publicURL = destination?.publicURL ?? ""
    }

    var destination: FolderDestination {
        FolderDestination(
            path: path,
            subfolderTemplate: Self.nonEmpty(subfolderTemplate),
            publicURL: Self.nonEmpty(publicURL)
        )
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
enum LocalFolderPicker {
    static var iCloudDriveURL: URL {
        RealHomeDirectory.url.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
    }

    static func choose(startingAt directory: URL? = nil, message: String? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose".localized()
        if let message {
            panel.message = message
        }
        if let directory {
            panel.directoryURL = directory
        }
        guard await panel.beginAsyncModal() == .OK else { return nil }
        return panel.url
    }
}

enum RealHomeDirectory {
    static var url: URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }
}

struct FolderDestinationSection: View {
    @Binding var draft: FolderDraft
    let suggestsICloudDrive: Bool

    var body: some View {
        Section {
            LabeledContent("Folder".localized()) {
                HStack {
                    Text(draft.path.isEmpty ? "None".localized() : (draft.path as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(draft.path.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…".localized(), action: choose)
                }
            }
            if suggestsICloudDrive {
                Text("ishare saves to a folder you choose in iCloud Drive, and iCloud syncs it to your other devices. Choose iCloud Drive or a folder inside it.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            TextField("Subfolder".localized(), text: $draft.subfolderTemplate, prompt: Text("{{date}}"))
            TextField("Public URL".localized(), text: $draft.publicURL, prompt: Text("https://example.com/{{filename}}"))
            Text(
                "Subfolder placeholders: {{date}}, {{year}}, {{month}}, {{day}}, {{name}}, {{ext}}, {{uuid}}, {{random}}, {{timestamp}}. Without a public URL, ishare copies the file URL. Public URL placeholders: {{filename}}, {{path}}, {{subfolder}}."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Folder".localized())
        }
    }

    private func choose() {
        Task { @MainActor in
            let start = suggestsICloudDrive && draft.path.isEmpty ? LocalFolderPicker.iCloudDriveURL : draft.bookmarkFreeURL
            guard let url = await LocalFolderPicker.choose(startingAt: start) else { return }
            draft.path = url.path
            draft.bookmark = LocalFolderAccess.makeBookmark(for: url)
        }
    }
}

private extension FolderDraft {
    var bookmarkFreeURL: URL? {
        path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }
}

enum PhotosAlbumMode: String, CaseIterable, Identifiable {
    case named
    case existing
    case library

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .named: "Album by name"
        case .existing: "Existing album"
        case .library: "Library only"
        }
    }
}

struct PhotosDraft: Equatable {
    var mode: PhotosAlbumMode = .named
    var albumName = PhotosDestination.defaultAlbumName
    var albumIdentifier = ""

    init() {}

    init(destination: PhotosDestination?) {
        guard let destination else { return }
        switch destination.target {
        case .library:
            mode = .library
        case let .named(name):
            mode = .named
            albumName = name
        case let .existing(identifier, fallbackName):
            mode = .existing
            albumIdentifier = identifier
            albumName = fallbackName ?? ""
        }
    }

    var destination: PhotosDestination {
        switch mode {
        case .named: PhotosDestination(albumName: albumName.trimmingCharacters(in: .whitespaces))
        case .existing: PhotosDestination(albumName: albumName, albumIdentifier: albumIdentifier.isEmpty ? nil : albumIdentifier)
        case .library: PhotosDestination(albumName: "")
        }
    }
}

struct PhotosDestinationSection: View {
    @Binding var draft: PhotosDraft
    @State private var hasAccess = PhotoLibrary.hasFullAccess
    @State private var albums: [PhotosAlbum] = []

    var body: some View {
        Section {
            if !hasAccess {
                Label("ishare needs access to Photos to add captures to an album.".localized(), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                Button("Open Privacy Settings".localized()) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                }
            }
            Picker("Album".localized(), selection: $draft.mode) {
                ForEach(PhotosAlbumMode.allCases) { Text($0.titleKey.localized()).tag($0) }
            }
            switch draft.mode {
            case .named:
                TextField("Album name".localized(), text: $draft.albumName, prompt: Text(PhotosDestination.defaultAlbumName))
            case .existing:
                Picker("Existing album".localized(), selection: $draft.albumIdentifier) {
                    Text("None".localized()).tag("")
                    ForEach(albums) { Text($0.title).tag($0.id) }
                }
                .onChange(of: draft.albumIdentifier) { _, identifier in
                    draft.albumName = albums.first { $0.id == identifier }?.title ?? draft.albumName
                }
            case .library:
                EmptyView()
            }
            Text(
                "ishare creates the album if it doesn't exist. Apps can't create shared albums or add to them, so captures go into a regular album that you can share from Photos. Photos uploads have no link; the history keeps a reference to the photo."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Photos".localized())
        }
        .task {
            if PhotoLibrary.isUndetermined {
                hasAccess = await PhotoLibrary.client.requestAccess(full: true)
            }
            hasAccess = PhotoLibrary.hasFullAccess
            if hasAccess {
                albums = PhotoLibrary.client.albums()
            }
        }
    }
}
