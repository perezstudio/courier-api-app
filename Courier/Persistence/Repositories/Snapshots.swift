import Foundation

// Value types handed out by repositories. Managed objects never leave
// Persistence/ — they are not Sendable, and keeping them out of the UI layer is
// what makes that layer testable. See REQUIREMENTS.md §3.1.

nonisolated struct WorkspaceSnapshot: Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let iconSymbolName: String
    let activeEnvironmentID: UUID?
    let requestCount: Int
}

/// One node in the collection tree. Folders carry children; requests are leaves.
nonisolated enum TreeNode: Sendable, Identifiable, Hashable {
    case folder(FolderSnapshot)
    case request(RequestSummary)

    var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .request(let request): request.id
        }
    }

    var sortOrder: Int {
        switch self {
        case .folder(let folder): folder.sortOrder
        case .request(let request): request.sortOrder
        }
    }

    var name: String {
        switch self {
        case .folder(let folder): folder.name
        case .request(let request): request.name
        }
    }
}

nonisolated struct FolderSnapshot: Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let isExpanded: Bool
    let children: [TreeNode]
}

/// The lightweight form used for sidebar rows and tab titles.
nonisolated struct RequestSummary: Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let method: String
    let sortOrder: Int
}

/// The full request, loaded when a tab opens.
nonisolated struct RequestDetail: Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let method: String
    let urlTemplate: String
    let bodyType: String
    let bodyContent: String?
    let graphqlVariables: String?
    let authType: String
    let authData: Data?
    let followRedirects: Bool
    let timeout: TimeInterval
    let headers: [KeyValueRow]
    let queryParams: [KeyValueRow]
}

nonisolated struct KeyValueRow: Sendable, Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String
    var isEnabled: Bool
    var note: String?

    init(id: UUID = UUID(), key: String, value: String, isEnabled: Bool = true, note: String? = nil) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.note = note
    }
}

nonisolated struct EnvironmentSnapshot: Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let variables: [VariableSnapshot]
}

nonisolated struct VariableSnapshot: Sendable, Identifiable, Hashable {
    let id: UUID
    let key: String
    /// Empty for secrets — the value is fetched from the Keychain on demand so
    /// it is never held in a long-lived snapshot. See REQUIREMENTS.md §6.
    let value: String
    let isSecret: Bool
    let isEnabled: Bool
    let sortOrder: Int
}

nonisolated struct RunSummary: Sendable, Identifiable, Hashable {
    let id: UUID
    let requestID: UUID?
    let status: RunStatus
    let isStarred: Bool
    let statusCode: Int?
    let statusText: String?
    let duration: TimeInterval?
    let size: Int?
    let errorMessage: String?
    let method: String
    let url: String
    let createdAt: Date
}

/// Where a folder or request sits in the tree. Used by move/reparent.
nonisolated enum TreeParent: Sendable, Hashable {
    case workspaceRoot(UUID)
    case folder(UUID)
}
