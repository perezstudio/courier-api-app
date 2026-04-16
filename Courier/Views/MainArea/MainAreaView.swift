import SwiftUI

struct MainAreaView: View {
    @Bindable var tabBarVM: TabBarViewModel
    @Bindable var requestEditorVM: RequestEditorViewModel
    @Bindable var inspectorVM: InspectorViewModel
    var onCloseTab: (UUID) -> Void
    var onSelectTab: (RequestTab) -> Void
    var onNewTab: (() -> Void)? = nil
    var onSend: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (in window background, above content card)
            TabBarView(
                viewModel: tabBarVM,
                onCloseTab: onCloseTab,
                onSelectTab: { tab in
                    tabBarVM.activeTabId = tab.id
                    onSelectTab(tab)
                },
                onNewTab: onNewTab
            )
            .zIndex(1)

            // Content card (pulled up to overlap with active tab)
            if tabBarVM.tabs.isEmpty {
                emptyContentCard
            } else {
                ContentCardControllerView(
                    requestEditorVM: requestEditorVM,
                    inspectorVM: inspectorVM,
                    onSend: onSend
                )
                .clipShape(RoundedRectangle(cornerRadius: ContentCardMetrics.cornerRadius))
                .padding(.top, -2)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
            }

            // Bottom padding
            Spacer()
                .frame(height: ContentCardMetrics.padding)
        }
        .padding(.trailing, ContentCardMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { VisualEffectBackground(material: .sidebar) }
        .ignoresSafeArea(edges: .top)
    }

    private var emptyContentCard: some View {
        RoundedRectangle(cornerRadius: ContentCardMetrics.cornerRadius)
            .fill(Color.courierCardSurface)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Select a request")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Choose a request from the sidebar or create a new one")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
    }
}
