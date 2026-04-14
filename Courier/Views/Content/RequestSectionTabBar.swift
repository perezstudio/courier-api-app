import SwiftUI

struct RequestSectionTabBar: View {
    @Binding var selectedTab: RequestEditorTab
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RequestEditorTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
        }
    }

    private func tabButton(_ tab: RequestEditorTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                            .matchedGeometryEffect(id: "sectionTab", in: tabNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
