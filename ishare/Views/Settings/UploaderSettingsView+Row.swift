import SwiftUI

extension UploaderSettingsView {
    func row(for uploader: CustomUploader) -> some View {
        HStack(spacing: 10) {
            Image(systemName: uploader.kind.symbolName)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color(for: uploader.kind).gradient))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(uploader.name)
                        .font(.system(size: 13, weight: .medium))
                    if uploader.id == activeCustomUploader, uploadType == .CUSTOM {
                        Text("Active".localized())
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                }
                Text(subtitle(for: uploader))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Group {
                iconButton("checkmark.circle", help: "Use") { activate(uploader) }
                if uploader.kind != .photos {
                    iconButton("paperplane", help: "Test Uploader") { testedUploader = uploader }
                }
                iconButton("pencil", help: "Edit Uploader") { editor = .edit(uploader) }
                iconButton("square.and.arrow.up", help: "Export Uploader") { export(uploader) }
                iconButton("trash", help: "Delete Uploader") { delete(uploader) }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Duplicate".localized()) { UploaderStore.duplicate(uploader) }
        }
    }

    private func subtitle(for uploader: CustomUploader) -> String {
        switch uploader.kind {
        case .s3:
            guard let s3 = uploader.s3 else { return "" }
            return "\(s3.bucket) · \(s3.endpointURL?.host() ?? s3.endpoint)"
        case .folder:
            return ((uploader.folder?.path ?? "") as NSString).abbreviatingWithTildeInPath
        case .photos:
            let name = uploader.photos?.albumName ?? ""
            return name.isEmpty ? "Photos library".localized() : name
        case .custom:
            return uploader.requestURL
        case .webdav:
            return uploader.webdav?.url ?? ""
        case .sftp:
            guard let sftp = uploader.sftp else { return "" }
            return "\(sftp.username)@\(sftp.host)" + (sftp.directory.map { ":\($0)" } ?? "")
        case .dropbox, .googleDrive, .oneDrive:
            let folder = uploader.cloud?.folderPath ?? CloudStorageConfiguration.defaultFolder
            return [uploader.cloud?.account, "/" + folder].compactMap { $0 }.joined(separator: " · ")
        case .github:
            return uploader.github?.repository ?? ""
        }
    }

    private func color(for kind: UploaderKind) -> Color {
        switch kind {
        case .custom: .teal
        case .s3: .orange
        case .folder: .blue
        case .photos: .pink
        case .webdav: .indigo
        case .sftp: .gray
        case .dropbox: .blue
        case .googleDrive: .green
        case .oneDrive: .cyan
        case .github: .purple
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help.localized())
    }
}
