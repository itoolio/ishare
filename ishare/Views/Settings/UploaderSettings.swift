//
//  UploaderSettings.swift
//  ishare
//
//  Created by Adrian Castro on 15.07.23.
//  UI reworked by iGerman on 22.04.24.
//

import Defaults
import SwiftUI

struct UploaderSettingsView: View {
    @Default(.activeCustomUploader) var activeCustomUploader
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.uploadType) var uploadType
    @Default(.aussieMode) var aussieMode

    @State private var isAddSheetPresented = false
    @State private var isImportSheetPresented = false
    @State private var editingUploader: CustomUploader?

    var body: some View {
        VStack {
            if let uploaders = savedCustomUploaders {
                if uploaders.isEmpty {
                    HStack(alignment: .center) {
                        VStack {
                            Text("You have no saved uploaders".localized())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    ForEach(uploaders.sorted(by: { $0.name < $1.name }), id: \.self) { uploader in
                        HStack {
                            Text(uploader.name)
                                .font(.subheadline)

                            Spacer()

                            Button(action: {
                                deleteCustomUploader(uploader)
                            }) {
                                Image(systemName: "trash")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Delete Uploader".localized())

                            Button(action: {
                                testCustomUploader(uploader)
                            }) {
                                Image(systemName: "icloud.and.arrow.up")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Test Uploader".localized())

                            Button(action: {
                                editingUploader = uploader
                                isAddSheetPresented.toggle()
                            }) {
                                Image(systemName: "pencil")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Edit Uploader".localized())

                            Button(action: {
                                exportUploader(uploader)
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Export Uploader".localized())
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }.padding(.top)
                }
            }

            Divider().padding(.horizontal)
            Spacer()

            HStack {
                Button(action: {
                    editingUploader = nil
                    isAddSheetPresented.toggle()
                }) {
                    Text("Create".localized())
                }
                .buttonStyle(DefaultButtonStyle())

                Button(action: {
                    isImportSheetPresented.toggle()
                }) {
                    Text("Import".localized())
                }
                .buttonStyle(DefaultButtonStyle())

                Button(action: {
                    clearAllUploaders()
                }) {
                    Text("Clear All".localized())
                        .foregroundColor(.red)
                }
                .buttonStyle(DefaultButtonStyle())
            }
            .padding(.bottom)
        }
        .rotationEffect(aussieMode ? .degrees(180) : .zero)
        .sheet(isPresented: $isAddSheetPresented) {
            AddCustomUploaderView(uploader: $editingUploader)
                .frame(minWidth: 450)
        }
        .sheet(isPresented: $isImportSheetPresented) {
            ImportCustomUploaderView()
                .frame(minWidth: 350)
        }
    }

    private func deleteCustomUploader(_ uploader: CustomUploader) {
        guard var uploaders = savedCustomUploaders else { return }
        uploaders = uploaders.filter { $0.id != uploader.id }
        savedCustomUploaders = uploaders

        if uploader.id == activeCustomUploader {
            activeCustomUploader = nil
            uploadType = .IMGUR
        }
    }

    private func testCustomUploader(_ uploader: CustomUploader) {
        guard let iconImage = NSImage(named: NSImage.applicationIconName) else {
            print("Failed to get app icon image")
            return
        }

        guard let tiffData = iconImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            print("Failed to convert image to PNG data")
            return
        }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let fileURL = temporaryDirectory.appendingPathComponent("appIconImage.png")

        do {
            try pngData.write(to: fileURL)
        } catch {
            print("Failed to write image file: \(error)")
            return
        }

        Task { @MainActor in
            let alert = NSAlert()
            do {
                let outcome = try await UploadService.upload(fileURL: fileURL, to: .custom(uploader))
                alert.alertStyle = .informational
                alert.messageText = "Upload Successful".localized()
                alert.informativeText = outcome.url.absoluteString
            } catch {
                alert.alertStyle = .critical
                alert.messageText = "Upload Error".localized()
                alert.informativeText = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: fileURL)
            alert.runModal()
        }
    }

    private func clearAllUploaders() {
        savedCustomUploaders = nil
        activeCustomUploader = nil
        uploadType = .IMGUR
    }

    private func exportUploader(_ uploader: CustomUploader) {
        let data = try! JSONEncoder().encode(uploader)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "iscu")!]
        savePanel.nameFieldStringValue = "\(uploader.name).iscu"

        // Launch the panel and handle the result
        Task { @MainActor in
            let response = await savePanel.beginAsyncModal()
            if response == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                } catch {
                    print("Error exporting uploader: \(error)")
                }
            }
        }
    }
}

struct AddCustomUploaderView: View {
    @Environment(\.presentationMode) var presentationMode
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.aussieMode) var aussieMode
    @Binding var uploader: CustomUploader?

    @State private var uploaderName: String = ""
    @State private var requestURL: String = ""
    @State private var responseURL: String = ""
    @State private var deletionURL: String = ""
    @State private var fileFormName: String = ""
    @State private var header: [CustomEntryModel] = []
    @State private var formData: [CustomEntryModel] = []

    var body: some View {
        ScrollView {
            Text(uploader == nil ? "Create Custom Uploader".localized() : "Edit Custom Uploader".localized())
                .font(.title)
                .padding()
            Divider().padding(.horizontal)

            VStack(alignment: .leading) {
                Group {
                    InputField(label: "Name*".lowercased(), text: $uploaderName)
                    HStack {
                        InputField(label: "Request URL*".localized(), text: $requestURL)
                        InputField(label: "Response URL*".localized(), text: $responseURL)
                    }
                    HStack {
                        InputField(label: "Deletion URL".localized(), text: $deletionURL)
                        InputField(label: "File Form Name".localized(), text: $fileFormName)
                    }
                }
                .padding(.bottom)

                Divider().padding(.vertical)
                HeaderView()
                Divider().padding(.vertical)
                FormDataView()
                Divider().padding(.vertical)

                Text("*required".localized()).font(.footnote).frame(maxWidth: .infinity, alignment: .leading).opacity(0.5)

                Button(action: {
                    saveCustomUploader()
                }) {
                    Text("Save".localized())
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .padding()
        }
        .onAppear {
            if let uploader {
                uploaderName = uploader.name
                requestURL = uploader.requestURL
                responseURL = uploader.responseURL
                deletionURL = uploader.deletionURL ?? ""
                fileFormName = uploader.fileFormName ?? ""
                header = uploader.headers?.map { CustomEntryModel(key: $0.key, value: $0.value) } ?? []
                formData = uploader.formData?.map { CustomEntryModel(key: $0.key, value: $0.value) } ?? []
            }
        }
        .rotationEffect(aussieMode ? .degrees(180) : .zero)
    }

    private struct InputField: View {
        let label: String
        @Binding var text: String

        var body: some View {
            VStack(alignment: .leading) {
                TextField(label, text: $text)
                    .padding(.top, 4)
            }
        }
    }

    private func HeaderView() -> some View {
        EntryListView(title: "Headers".localized(), entries: $header)
    }

    private func FormDataView() -> some View {
        EntryListView(title: "Form Data".localized(), entries: $formData)
    }

    struct EntryListView: View {
        let title: String
        @Binding var entries: [CustomEntryModel]

        var body: some View {
            Section(header: HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: {
                    entries.append(CustomEntryModel(key: "", value: ""))
                }) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(entries) { entry in
                    if entry == entries.last {
                        CustomEntryView(entry: $entries[entries.firstIndex(of: entry)!])
                            .padding(.horizontal)
                    }
                }

                if !entries.isEmpty {
                    Divider()
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Name".localized()).frame(maxWidth: .infinity)
                        }
                        Divider()
                        VStack(alignment: .leading) {
                            Text("Value".localized()).frame(maxWidth: .infinity)
                        }
                        Button(action: {}) {
                            Image(systemName: "minus.circle")
                        }.opacity(0)
                            .disabled(true)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                }

                ForEach(entries.indices, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entries[index].key)
                                .padding(1)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .font(.system(.body, design: .monospaced))
                        }
                        Divider()
                        VStack(alignment: .leading) {
                            Text(entries[index].value)
                                .padding(1)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .font(.system(.body, design: .monospaced))
                        }
                        Button(action: {
                            entries.remove(at: index)
                        }) {
                            Image(systemName: "minus.circle").foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Rectangle()
                        .frame(width: .infinity, height: 1)
                        .opacity(0.1)
                        .padding(0)
                }
            }
        }
    }

    private func saveCustomUploader() {
        var headerData: [String: String] {
            header.reduce(into: [String: String]()) { result, entry in
                result[entry.key] = entry.value
            }
        }

        var formDataModel: [String: String] {
            formData.reduce(into: [String: String]()) { result, entry in
                result[entry.key] = entry.value
            }
        }

        let newUploader = CustomUploader(
            name: uploaderName,
            requestURL: requestURL,
            headers: header.isEmpty ? nil : headerData,
            formData: formData.isEmpty ? nil : formDataModel,
            fileFormName: fileFormName.isEmpty ? nil : fileFormName,
            responseURL: responseURL,
            deletionURL: deletionURL.isEmpty ? nil : deletionURL
        )

        if var uploaders = savedCustomUploaders {
            uploaders.remove(newUploader)
            uploaders.insert(newUploader)
            savedCustomUploaders = uploaders
        } else {
            savedCustomUploaders = Set([newUploader])
        }

        presentationMode.wrappedValue.dismiss()
    }

    private struct CustomEntryView: View {
        @Binding var entry: CustomEntryModel

        var body: some View {
            HStack {
                VStack(alignment: .leading) {
                    TextField("Name".localized(), text: $entry.key)
                }
                VStack(alignment: .leading) {
                    TextField("Value".localized(), text: $entry.value)
                }
            }
        }
    }
}

struct ImportCustomUploaderView: View {
    @Environment(\.presentationMode) var presentationMode
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.activeCustomUploader) var activeCustomUploader
    @Default(.uploadType) var uploadType
    @Default(.aussieMode) var aussieMode

    @State private var selectedFileURLs: [URL] = []
    @State private var importError: ImportError?

    func selectFile(completion: @escaping @Sendable (URL?) -> Void) {
        let filePicker = NSOpenPanel()
        filePicker.canChooseDirectories = false
        filePicker.canChooseFiles = true
        filePicker.allowsMultipleSelection = false
        filePicker.canDownloadUbiquitousContents = true
        filePicker.canResolveUbiquitousConflicts = true

        Task { @MainActor in
            let response = await filePicker.beginAsyncModal()
            if response == .OK {
                completion(filePicker.urls.first)
            } else {
                completion(nil)
            }
        }
    }

    var body: some View {
        VStack {
            Text("Import Custom Uploader".localized())
                .font(.title)

            Divider()

            // Drag and Drop Receptacle
            RoundedRectangle(cornerRadius: 12)
                .frame(height: 150)
                .foregroundColor(.gray.opacity(0.2))
                .overlay(
                    VStack {
                        Image(systemName: "arrow.down.doc")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                        Text("Drag and drop .iscu files here or click to select".localized())
                            .foregroundColor(.gray)
                    }
                )
                .onTapGesture {
                    selectFile { fileURL in
                        if let url = fileURL {
                            Task { @MainActor in
                                selectedFileURLs.append(url)
                                importUploader()
                            }
                        }
                    }
                }
                .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                    providers.first?.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            Task { @MainActor in
                                selectedFileURLs.append(url)
                                importUploader()
                            }
                        }
                    }
                    return true
                }

            if let fileURL = selectedFileURLs.first {
                Text("Selected File: \(fileURL.lastPathComponent)".localized())
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel".localized()) {
                presentationMode.wrappedValue.dismiss()
            }
            .padding()
        }
        .padding()
        .alert(item: $importError) { error in
            Alert(
                title: Text("Error".localized()),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK".localized()))
            )
        }
        .rotationEffect(aussieMode ? .degrees(180) : .zero)
    }

    private func importUploader() {
        guard let fileURL = selectedFileURLs.first else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let uploader = try CustomUploader.fromJSON(data)

            if var uploaders = savedCustomUploaders {
                uploaders.remove(uploader)
                uploaders.insert(uploader)
                savedCustomUploaders = uploaders
            } else {
                savedCustomUploaders = Set([uploader])
            }

            activeCustomUploader = uploader.id
            uploadType = .CUSTOM
            presentationMode.wrappedValue.dismiss()
        } catch {
            importError = ImportError(error: error)
            print("Error importing custom uploader: \(error)")
            return
        }

        selectedFileURLs = []
        presentationMode.wrappedValue.dismiss()
    }
}

struct ImportError: Identifiable {
    let id = UUID()
    let error: any Error

    var localizedDescription: String {
        error.localizedDescription
    }
}

struct CustomEntryModel: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}

#Preview {
    UploaderSettingsView()
}
