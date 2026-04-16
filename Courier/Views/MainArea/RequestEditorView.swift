import SwiftUI

/// Standalone SwiftUI request editor, extracted from ContentCardView.
/// Observes inspectorVM.isCollapsed directly for the toggle button state.
struct RequestEditorView: View {
    @Bindable var requestEditorVM: RequestEditorViewModel
    @Bindable var inspectorVM: InspectorViewModel
    var onSend: (() -> Void)?
    var onToggleInspector: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // URL Bar + Inspector toggle
            HStack(spacing: 8) {
                URLBarView(
                    method: $requestEditorVM.method,
                    urlString: $requestEditorVM.urlString,
                    onMethodChange: { requestEditorVM.updateMethod($0) },
                    onURLChange: { requestEditorVM.updateURL($0) },
                    onSend: { onSend?() }
                )

                // Inspector toggle — only visible when inspector is collapsed
                if inspectorVM.isCollapsed {
                    Button {
                        onToggleInspector?()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.courierHover())
                    .help("Show Inspector")
                }
            }
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
                    KeyValueEditor(
                        rows: $requestEditorVM.queryParams,
                        keyPlaceholder: "Parameter",
                        valuePlaceholder: "Value",
                        onChange: { requestEditorVM.syncParamsToURL() }
                    )
                case .headers:
                    KeyValueEditor(
                        rows: $requestEditorVM.headerRows,
                        keyPlaceholder: "Header",
                        valuePlaceholder: "Value",
                        onChange: { requestEditorVM.saveHeaders() }
                    )
                case .body:
                    BodyEditorView(
                        bodyType: $requestEditorVM.bodyType,
                        bodyContent: $requestEditorVM.bodyContent,
                        onChange: { requestEditorVM.saveBody() }
                    )
                case .auth:
                    AuthEditorView(
                        authType: $requestEditorVM.authType,
                        authData: $requestEditorVM.authData,
                        onChange: { requestEditorVM.saveAuth() }
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
