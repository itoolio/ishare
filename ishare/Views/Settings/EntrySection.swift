import SwiftUI

struct EntrySection: View {
    let title: String
    @Binding var entries: [CustomEntryModel]

    var body: some View {
        Section {
            ForEach($entries) { $entry in
                HStack {
                    TextField("Name".localized(), text: $entry.key)
                        .font(.system(.body, design: .monospaced))
                    TextField("Value".localized(), text: $entry.value)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        entries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            HStack {
                Text(title.localized())
                Spacer()
                Button {
                    entries.append(CustomEntryModel(key: "", value: ""))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct CustomEntryModel: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}
