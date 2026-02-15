import SwiftUI

struct ListEditorView: View {
    let title: String
    @Binding var items: [String]
    let isEditable: Bool

    var body: some View {
        Section(title) {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    if isEditable {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                    }
                    TextField("Value", text: $items[index])
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isEditable)
                    if isEditable {
                        Button(action: { items.remove(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onMove { from, to in
                guard isEditable else { return }
                items.move(fromOffsets: from, toOffset: to)
            }
            if isEditable {
                Button(action: { items.append("") }) {
                    Label("Add", systemImage: "plus.circle")
                }
            }
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
