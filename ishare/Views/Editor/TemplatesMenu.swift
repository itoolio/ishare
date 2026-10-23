import AppKit
import SwiftUI

struct TemplatesButton: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var store: TemplateStore

    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Templates".localized())
        .accessibilityLabel("Templates".localized())
        .accessibilityIdentifier("editor.templates")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            TemplatesPanel(document: document, store: store) { showing = false }
        }
    }
}

private struct TemplatesPanel: View {
    enum Naming: Equatable {
        case saving
        case renaming(UUID)
    }

    @ObservedObject var document: EditorDocument
    @ObservedObject var store: TemplateStore
    var dismiss: () -> Void

    @State private var naming: Naming?
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let naming {
                nameForm(for: naming)
            } else {
                saveButton
                Divider()
                Text("Insert Template".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                templateList
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private var saveTitle: String {
        document.selectedAnnotations.contains { !$0.hidden } ? "Save Selection as Template…".localized() : "Save as Template…".localized()
    }

    private var saveButton: some View {
        Button {
            name = store.defaultName()
            naming = .saving
        } label: {
            Label(saveTitle, systemImage: "square.and.arrow.down")
        }
        .disabled(document.templateSource.isEmpty)
        .accessibilityIdentifier("editor.templates.save")
    }

    @ViewBuilder
    private var templateList: some View {
        if store.templates.isEmpty {
            Text("No templates yet".localized())
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.templates) { template in
                        row(for: template)
                    }
                }
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for template: AnnotationTemplate) -> some View {
        HStack(spacing: 8) {
            Button {
                document.insert(template)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: store.preview(for: template))
                        .frame(width: TemplateStore.previewSize.width, height: TemplateStore.previewSize.height)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(verbatim: template.name)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Insert Template".localized())
            .accessibilityLabel(Text(verbatim: template.name))
            .accessibilityIdentifier("editor.templates.insert")
            Menu {
                Button("Rename…".localized()) {
                    name = template.name
                    naming = .renaming(template.id)
                }
                .accessibilityIdentifier("editor.templates.rename")
                Button("Delete".localized(), role: .destructive) {
                    perform { try store.delete(template.id) }
                }
                .accessibilityIdentifier("editor.templates.delete")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .helpAndAccessibilityLabel("More".localized())
            .accessibilityIdentifier("editor.templates.more")
        }
        .padding(4)
    }

    private func nameForm(for naming: Naming) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(naming == .saving ? "Save as Template".localized() : "Rename Template".localized())
                .font(.headline)
            TextField("Template Name".localized(), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { submit(naming) }
                .accessibilityIdentifier("editor.templates.name")
            HStack {
                Spacer()
                Button("Cancel".localized()) { self.naming = nil }
                    .keyboardShortcut(.cancelAction)
                Button(naming == .saving ? "Save".localized() : "Rename".localized()) { submit(naming) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("editor.templates.confirm")
            }
        }
        .onAppear { nameFocused = true }
    }

    private func submit(_ naming: Naming) {
        switch naming {
        case .saving:
            perform { _ = try store.save(name: name, annotations: document.templateSource, frame: document.templateFrame) }
        case let .renaming(id):
            perform { try store.rename(id, to: name) }
        }
        self.naming = nil
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            Log.app.error("Updating templates failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }
}
