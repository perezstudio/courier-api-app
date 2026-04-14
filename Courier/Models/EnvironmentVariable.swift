import Foundation
import SwiftData

@Model
final class EnvironmentVariable {
    var id: UUID
    var key: String
    var value: String
    var isSecret: Bool
    var environment: Environment?

    init(key: String = "", value: String = "", isSecret: Bool = false) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}
