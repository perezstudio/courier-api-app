import Foundation

/// Reference-type wrapper around a `TreeNode` snapshot.
///
/// `NSOutlineView` addresses rows by object identity, so the value-type
/// snapshots the repository hands out cannot be used directly. Equality and
/// hashing are by `id` rather than instance, which is what lets expansion and
/// selection survive a rebuild: after a reload the outline view sees the *same*
/// items even though the objects are new.
final class SidebarNode: NSObject {

    enum Kind {
        case folder
        case request
    }

    let id: UUID
    let kind: Kind
    let name: String
    /// Non-nil for requests only.
    let method: String?
    let children: [SidebarNode]
    private(set) weak var parent: SidebarNode?

    var isFolder: Bool { kind == .folder }

    init(id: UUID, kind: Kind, name: String, method: String?, children: [SidebarNode]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.method = method
        self.children = children
        super.init()
        for child in children {
            child.parent = self
        }
    }

    // MARK: - Building

    /// Builds a node tree, dropping anything that doesn't match `filter`.
    ///
    /// A folder survives if it matches by name or has a surviving descendant —
    /// otherwise filtering would hide the path to a matching request.
    static func build(from nodes: [TreeNode], filter: String) -> [SidebarNode] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return nodes.compactMap { node(from: $0, needle: needle) }
    }

    private static func node(from treeNode: TreeNode, needle: String) -> SidebarNode? {
        switch treeNode {
        case .request(let request):
            guard needle.isEmpty || request.name.lowercased().contains(needle) else { return nil }
            return SidebarNode(
                id: request.id,
                kind: .request,
                name: request.name,
                method: request.method,
                children: []
            )

        case .folder(let folder):
            let children = folder.children.compactMap { node(from: $0, needle: needle) }
            let matchesSelf = needle.isEmpty || folder.name.lowercased().contains(needle)
            guard matchesSelf || !children.isEmpty else { return nil }
            return SidebarNode(
                id: folder.id,
                kind: .folder,
                name: folder.name,
                method: nil,
                children: children
            )
        }
    }

    /// Depth-first search for a node by id.
    static func find(_ id: UUID, in nodes: [SidebarNode]) -> SidebarNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = find(id, in: node.children) { return found }
        }
        return nil
    }

    // MARK: - Identity

    nonisolated override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SidebarNode else { return false }
        return other.id == id
    }

    nonisolated override var hash: Int {
        id.hashValue
    }
}
