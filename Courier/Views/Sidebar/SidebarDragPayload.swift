import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Transferable payload used for in-app drag-and-drop reordering of sidebar rows.
/// Encodes the kind (folder / request) and the entity's UUID.
struct SidebarDragPayload: Codable, Transferable {
    enum Kind: String, Codable {
        case folder
        case request
    }

    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
