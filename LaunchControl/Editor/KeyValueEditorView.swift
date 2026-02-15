import SwiftUI

struct KeyValueEditorView: View {
    let title: String
    @Binding var pairs: [String: String]
    let isEditable: Bool

    @State private var sortedKeys: [String] = []

    var body: some View {
        Section(title) {
            ForEach(sortedKeys, id: \.self) { key in
                HStack {
                    TextField("Key", text: Binding(
                        get: { key },
                        set: { newKey in
                            guard newKey != key, let value = pairs[key] else { return }
                            pairs.removeValue(forKey: key)
                            pairs[newKey] = value
                            refreshKeys()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .disabled(!isEditable)

                    TextField("Value", text: Binding(
                        get: { pairs[key] ?? "" },
                        set: { pairs[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditable)

                    if isEditable {
                        Button(action: {
                            pairs.removeValue(forKey: key)
                            refreshKeys()
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if isEditable {
                Button(action: {
                    let newKey = uniqueKey()
                    pairs[newKey] = ""
                    refreshKeys()
                }) {
                    Label("Add", systemImage: "plus.circle")
                }
            }
            if pairs.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refreshKeys() }
        .onChange(of: pairs) { _, _ in refreshKeys() }
    }

    private func refreshKeys() {
        sortedKeys = pairs.keys.sorted()
    }

    private func uniqueKey() -> String {
        var key = "NEW_KEY"
        var i = 1
        while pairs[key] != nil {
            key = "NEW_KEY_\(i)"
            i += 1
        }
        return key
    }
}
