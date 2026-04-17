import Foundation

/// Unified sibling for the sidebar hierarchy. Folders and requests at the
/// same level share a single `sortOrder` space, letting us render and
/// reorder them as one list.
enum SidebarItem: Identifiable, Hashable {
    case folder(Folder)
    case request(APIRequest)

    enum Kind: Hashable { case folder, request }

    var id: UUID {
        switch self {
        case .folder(let f): return f.id
        case .request(let r): return r.id
        }
    }

    var kind: Kind {
        switch self {
        case .folder: return .folder
        case .request: return .request
        }
    }

    var sortOrder: Int {
        switch self {
        case .folder(let f): return f.sortOrder
        case .request(let r): return r.sortOrder
        }
    }
}

extension Folder {
    /// Folders + requests contained directly in this folder, as unified siblings.
    var children: [SidebarItem] {
        let folderItems = subFolders.map { SidebarItem.folder($0) }
        let requestItems = requests.map { SidebarItem.request($0) }
        return (folderItems + requestItems).sorted { $0.sortOrder < $1.sortOrder }
    }
}

extension Workspace {
    /// Top-level folders (those without a parent folder) and workspace-root
    /// requests, unified as siblings.
    var rootItems: [SidebarItem] {
        let rootFolders = folders.filter { $0.parentFolder == nil }.map { SidebarItem.folder($0) }
        let rootRequests = requests.map { SidebarItem.request($0) }
        return (rootFolders + rootRequests).sorted { $0.sortOrder < $1.sortOrder }
    }
}
