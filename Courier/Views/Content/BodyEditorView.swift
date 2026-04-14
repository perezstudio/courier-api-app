import SwiftUI

enum BodyType: String, CaseIterable, Identifiable {
    case none = "None"
    case json = "JSON"
    case xml = "XML"
    case formData = "Form Data"
    case urlEncoded = "URL Encoded"
    case binary = "Binary"
    case graphql = "GraphQL"

    var id: String { rawValue }
}

struct BodyEditorView: View {
    @Binding var bodyType: String?
    @Binding var bodyContent: String?
    var onChange: (() -> Void)? = nil

    @State private var formRows: [KeyValueRow] = []

    private var selectedType: BodyType {
        BodyType(rawValue: bodyType ?? "None") ?? .none
    }

    var body: some View {
        VStack(spacing: 0) {
            // Type selector
            HStack(spacing: 4) {
                ForEach(BodyType.allCases) { type in
                    Button {
                        bodyType = type.rawValue
                        onChange?()
                    } label: {
                        Text(type.rawValue)
                            .font(.system(size: 11, weight: selectedType == type ? .semibold : .regular))
                            .foregroundStyle(selectedType == type ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedType == type ? Color.primary.opacity(0.08) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Body content
            Group {
                switch selectedType {
                case .none:
                    emptyBodyState
                case .json, .xml, .graphql:
                    textEditorBody
                case .formData, .urlEncoded:
                    KeyValueEditor(
                        rows: $formRows,
                        keyPlaceholder: "Key",
                        valuePlaceholder: "Value",
                        onChange: onChange
                    )
                case .binary:
                    binaryPickerBody
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyBodyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("This request does not have a body")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var textEditorBody: some View {
        TextEditor(text: Binding(
            get: { bodyContent ?? "" },
            set: { bodyContent = $0; onChange?() }
        ))
        .font(.system(size: 12, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(8)
    }

    private var binaryPickerBody: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Button("Select File") {
                // TODO: NSOpenPanel file picker
            }
            .buttonStyle(.courierHoverText())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
