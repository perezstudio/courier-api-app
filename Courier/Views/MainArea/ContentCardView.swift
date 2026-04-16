import SwiftUI

struct ContentCardView: View {
    @Bindable var requestEditorVM: RequestEditorViewModel
    @Bindable var inspectorVM: InspectorViewModel
    var onSend: (() -> Void)? = nil

    @State private var inspectorWidth: CGFloat = 350
    @State private var isDraggingDivider = false

    private let minInspectorWidth: CGFloat = 250
    private let minEditorWidth: CGFloat = 350

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Request Editor (left side)
                requestEditorPanel
                    .frame(maxWidth: .infinity)

                if !inspectorVM.isCollapsed {
                    // Draggable divider
                    dividerHandle

                    // Inspector (right side)
                    inspectorPanel
                        .frame(width: clampedInspectorWidth(in: geo.size.width))
                }
            }
        }
        .background(Color.courierCardSurface)
        .clipShape(
            RoundedRectangle(cornerRadius: ContentCardMetrics.cornerRadius)
        )
    }

    private func clampedInspectorWidth(in totalWidth: CGFloat) -> CGFloat {
        let maxHalf = totalWidth * 0.5
        let maxAllowed = totalWidth - minEditorWidth - 6 // 6 for divider
        return min(max(inspectorWidth, minInspectorWidth), min(maxHalf, maxAllowed))
    }

    // MARK: - Divider

    private var dividerHandle: some View {
        Rectangle()
            .fill(isDraggingDivider ? Color.accentColor.opacity(0.5) : Color.courierSeparator)
            .frame(width: isDraggingDivider ? 2 : 1)
            .padding(.vertical, 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDraggingDivider = true
                        inspectorWidth -= value.translation.width
                        inspectorWidth = max(minInspectorWidth, inspectorWidth)
                    }
                    .onEnded { _ in
                        isDraggingDivider = false
                    }
            )
    }

    // MARK: - Request Editor

    private var requestEditorPanel: some View {
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

                // Inspector toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        inspectorVM.isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: inspectorVM.isCollapsed ? "sidebar.trailing" : "sidebar.trailing")
                        .font(.system(size: 12))
                        .foregroundStyle(inspectorVM.isCollapsed ? .tertiary : .secondary)
                }
                .buttonStyle(.courierHover())
                .help(inspectorVM.isCollapsed ? "Show Inspector" : "Hide Inspector")
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

    // MARK: - Inspector

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            if let run = inspectorVM.activeRun {
                switch run.status {
                case .completed, .failed:
                    if run.statusCode != nil {
                        inspectorToolbar(run)
                        Divider()
                        switch inspectorVM.selectedTab {
                        case .body:
                            responseBodyView(run)
                        case .headers:
                            responseHeadersView(run)
                        }
                    } else {
                        errorState(run.errorMessage ?? "Unknown error")
                    }

                case .pending, .running:
                    loadingState
                }
            } else {
                emptyInspectorState
            }
        }
    }

    /// Single toolbar matching the content area toolbar height, with status left + tabs right.
    private func inspectorToolbar(_ run: APICallRun) -> some View {
        HStack(spacing: 8) {
            // Left: status code title + metrics subtitle
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let code = run.statusCode {
                        Text("\(code)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusColor(code))
                    }
                    if let text = run.statusText {
                        Text(text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                HStack(spacing: 6) {
                    if let duration = run.duration {
                        Text("\(Int(duration * 1000))ms")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let size = run.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Right: Body / Headers tabs
            HStack(spacing: 4) {
                ForEach(InspectorTab.allCases) { tab in
                    Button {
                        inspectorVM.selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: inspectorVM.selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(inspectorVM.selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(inspectorVM.selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func responseBodyView(_ run: APICallRun) -> some View {
        if let body = run.responseBody {
            if body.bodyString != nil {
                ResponseTextView(
                    plainText: body.bodyString,
                    contentType: run.responseHeaders?.decoded["Content-Type"]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let rawBody = body.rawBody {
                Text("\(rawBody.count) bytes (binary)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                Text("No body")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }
        } else {
            Text("No body")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
        }
    }

    private func responseHeadersView(_ run: APICallRun) -> some View {
        let headers = run.responseHeaders?.decoded ?? [:]
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(alignment: .top) {
                        Text(key)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                        Text(value)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var loadingState: some View {
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
    }

    private func errorState(_ error: String) -> some View {
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
    }

    private var emptyInspectorState: some View {
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

    // MARK: - Helpers

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
