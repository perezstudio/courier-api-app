import SwiftUI

struct KeyValueRow: Identifiable {
    let id: UUID
    var key: String
    var value: String
    var isEnabled: Bool

    init(id: UUID = UUID(), key: String = "", value: String = "", isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}

struct KeyValueEditor: View {
    @Binding var rows: [KeyValueRow]
    var keyPlaceholder: String = "Key"
    var valuePlaceholder: String = "Value"
    var onChange: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 32)
                Text(keyPlaceholder)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(valuePlaceholder)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("")
                    .frame(width: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        keyValueRow(index: index, row: row)
                        if index < rows.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }

            Divider()

            // Add row button
            HStack {
                Button {
                    rows.append(KeyValueRow())
                    onChange?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Add")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.courierHoverText(size: .small))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func keyValueRow(index: Int, row: KeyValueRow) -> some View {
        HStack(spacing: 0) {
            // Enable/disable toggle
            Button {
                rows[index].isEnabled.toggle()
                onChange?()
            } label: {
                Image(systemName: rows[index].isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(rows[index].isEnabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 32)

            // Key field
            TextField(keyPlaceholder, text: Binding(
                get: { rows[index].key },
                set: { rows[index].key = $0; onChange?() }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.trailing, 8)

            // Value field
            TextField(valuePlaceholder, text: Binding(
                get: { rows[index].value },
                set: { rows[index].value = $0; onChange?() }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.trailing, 4)

            // Delete button
            Button {
                rows.remove(at: index)
                onChange?()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .opacity(rows[index].isEnabled ? 1.0 : 0.5)
    }
}
