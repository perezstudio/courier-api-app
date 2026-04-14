import Foundation
import SwiftData

struct RequestTab: Identifiable, Equatable {
    let id: UUID
    let requestId: UUID
    var name: String
    var method: String
}

@Observable
final class TabBarViewModel {
    var tabs: [RequestTab] = []
    var activeTabId: UUID?

    var activeTab: RequestTab? {
        tabs.first { $0.id == activeTabId }
    }

    func openRequest(_ request: APIRequest) {
        if let existing = tabs.first(where: { $0.requestId == request.id }) {
            activeTabId = existing.id
            return
        }

        let tab = RequestTab(
            id: UUID(),
            requestId: request.id,
            name: request.name,
            method: request.method
        )
        tabs.append(tab)
        activeTabId = tab.id
    }

    func closeTab(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let wasActive = activeTabId == tabId
        tabs.remove(at: index)

        if wasActive {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }
        }
    }

    func closeAllTabs() {
        tabs.removeAll()
        activeTabId = nil
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
    }
}
