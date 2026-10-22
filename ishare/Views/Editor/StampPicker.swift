import AppKit
import SwiftUI

struct StampPreview: View {
    var stamp: Stamp
    var color: RGBAColor
    var size: CGFloat

    var body: some View {
        switch stamp {
        case let .emoji(value):
            Text(verbatim: value)
                .font(.system(size: size * 0.85))
                .frame(width: size, height: size)
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(Color(nsColor: color.nsColor))
                .frame(width: size, height: size)
        }
    }
}

struct StampPicker: View {
    @ObservedObject var document: EditorDocument
    var onPick: (Stamp) -> Void

    @State private var paletteInput = ""
    @FocusState private var inputFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Symbols".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Stamp.symbols, id: \.self) { name in
                    stampButton(.symbol(name))
                }
            }
            Text("Emoji".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Stamp.commonEmoji, id: \.self) { emoji in
                    stampButton(.emoji(emoji))
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Type an emoji".localized(), text: $paletteInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .frame(width: 120)
                    .accessibilityIdentifier("editor.stamp.input")
                Button {
                    inputFocused = true
                    DispatchQueue.main.async {
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                } label: {
                    Label("Emoji & Symbols…".localized(), systemImage: "globe")
                }
                .accessibilityIdentifier("editor.stamp.characterPalette")
            }
        }
        .padding(12)
        .onChange(of: paletteInput) { _, text in
            guard let emoji = Stamp.firstEmoji(in: text) else { return }
            paletteInput = ""
            onPick(.emoji(emoji))
        }
    }

    private func stampButton(_ stamp: Stamp) -> some View {
        Button {
            onPick(stamp)
        } label: {
            StampPreview(stamp: stamp, color: document.color, size: 26)
                .frame(width: 30, height: 30)
                .background {
                    if document.stamp == stamp {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.25))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(stamp.accessibilityName)
        .accessibilityIdentifier("editor.stamp.\(stamp.accessibilityName)")
    }
}
