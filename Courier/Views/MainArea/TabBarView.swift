import SwiftUI

struct TabBarView: View {
    @Bindable var viewModel: TabBarViewModel
    var onCloseTab: (UUID) -> Void
    var onSelectTab: (RequestTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Tabs
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(viewModel.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: viewModel.activeTabId == tab.id,
                            onSelect: { onSelectTab(tab) },
                            onClose: { onCloseTab(tab.id) }
                        )
                    }
                }
                .padding(.leading, 4)
            }
            .scrollIndicators(.hidden)

            Spacer()
        }
        .frame(height: ContentCardMetrics.tabBarHeight)
        .padding(.top, 6) // Align with sidebar toolbar
    }
}
