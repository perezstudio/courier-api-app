import SwiftUI

enum AuthType: String, CaseIterable, Identifiable {
    case none = "None"
    case bearer = "Bearer Token"
    case basic = "Basic Auth"
    case apiKey = "API Key"

    var id: String { rawValue }
}

struct AuthEditorView: View {
    @Binding var authType: String?
    @Binding var authData: String?
    var onChange: (() -> Void)? = nil

    @State private var bearerToken: String = ""
    @State private var basicUsername: String = ""
    @State private var basicPassword: String = ""
    @State private var apiKeyKey: String = ""
    @State private var apiKeyValue: String = ""
    @State private var apiKeyAddTo: String = "Header"

    private var selectedType: AuthType {
        AuthType(rawValue: authType ?? "None") ?? .none
    }

    var body: some View {
        VStack(spacing: 0) {
            // Type selector
            HStack(spacing: 4) {
                ForEach(AuthType.allCases) { type in
                    Button {
                        authType = type.rawValue
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

            // Auth form
            Group {
                switch selectedType {
                case .none:
                    noAuthState
                case .bearer:
                    bearerForm
                case .basic:
                    basicForm
                case .apiKey:
                    apiKeyForm
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var noAuthState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No authentication")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var bearerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            authField(label: "Token", text: $bearerToken, placeholder: "Enter bearer token or {{variable}}")
            Spacer()
        }
        .padding(16)
    }

    private var basicForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            authField(label: "Username", text: $basicUsername, placeholder: "Enter username")
            authField(label: "Password", text: $basicPassword, placeholder: "Enter password", isSecure: true)
            Spacer()
        }
        .padding(16)
    }

    private var apiKeyForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            authField(label: "Key", text: $apiKeyKey, placeholder: "e.g. X-API-Key")
            authField(label: "Value", text: $apiKeyValue, placeholder: "Enter API key or {{variable}}")

            HStack {
                Text("Add to")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)

                Picker("", selection: $apiKeyAddTo) {
                    Text("Header").tag("Header")
                    Text("Query Param").tag("Query Param")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Spacer()
        }
        .padding(16)
    }

    private func authField(label: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
        }
    }
}
