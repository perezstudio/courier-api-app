import SwiftUI

struct TabBarView: View {
    @Bindable var viewModel: TabBarViewModel
    var onCloseTab: (UUID) -> Void
    var onSelectTab: (RequestTab) -> Void
    var onNewTab: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Tabs
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(viewModel.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: viewModel.activeTabId == tab.id,
                            onSelect: { onSelectTab(tab) },
                            onClose: { onCloseTab(tab.id) }
                        )
                    }

                    // New tab button
                    if let onNewTab {
                        Button {
                            onNewTab()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.courierHover(size: .small))
                        .padding(.leading, 4)
                        .padding(.bottom, 6)
                    }
                }
                .padding(.leading, 4)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)

            Spacer()
        }
        .frame(height: 32)
        .padding(.top, 6)
    }
}
