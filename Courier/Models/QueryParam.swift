import Foundation
import SwiftData

@Model
final class QueryParam {
    var id: UUID
    var key: String
    var value: String
    var isEnabled: Bool
    var request: APIRequest?

    init(key: String = "", value: String = "", isEnabled: Bool = true) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}
