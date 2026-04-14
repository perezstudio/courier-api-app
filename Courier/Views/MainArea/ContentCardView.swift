import SwiftUI

struct ContentCardView: View {
    @Bindable var requestEditorVM: RequestEditorViewModel
    @Bindable var inspectorVM: InspectorViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Request Editor (left side)
            requestEditorPanel
                .frame(maxWidth: .infinity)

            if !inspectorVM.isCollapsed {
                // Divider
                Rectangle()
                    .fill(Color.courierSeparator)
                    .frame(width: 1)

                // Inspector (right side)
                inspectorPanel
                    .frame(width: 350)
            }
        }
        .background(Color.courierCardSurface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: ContentCardMetrics.cornerRadius,
                bottomTrailingRadius: ContentCardMetrics.cornerRadius,
                topTrailingRadius: ContentCardMetrics.cornerRadius
            )
        )
    }

    // MARK: - Request Editor

    private var requestEditorPanel: some View {
        VStack(spacing: 0) {
            // URL Bar
            URLBarView(
                method: $requestEditorVM.method,
                urlString: $requestEditorVM.urlString,
                onMethodChange: { requestEditorVM.updateMethod($0) },
                onURLChange: { requestEditorVM.updateURL($0) },
                onSend: { /* TODO: Phase 5 */ }
            )
            .padding(12)

            Divider()

            // Section tab bar
            RequestSectionTabBar(selectedTab: $requestEditorVM.selectedTab)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Tab content
            Group {
                switch requestEditorVM.selectedTab {
                case .params:
                    placeholderSection("Query parameters will appear here")
                case .headers:
                    placeholderSection("Request headers will appear here")
                case .body:
                    placeholderSection("Request body editor will appear here")
                case .auth:
                    placeholderSection("Authentication settings will appear here")
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Inspector

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            if let response = inspectorVM.response {
                // Response header
                HStack {
                    Text("\(response.statusCode)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor(response.statusCode))
                    Text(response.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(response.duration * 1000))ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(response.size), countStyle: .memory))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(12)

                Divider()

                // Response body placeholder
                ScrollView {
                    if let bodyString = response.bodyString {
                        Text(bodyString)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            } else if inspectorVM.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Sending...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = inspectorVM.error {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(12)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "paperplane")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Send a request to see the response")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func placeholderSection(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .yellow
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .secondary
        }
    }
}
