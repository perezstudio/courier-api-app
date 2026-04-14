import Foundation
import SwiftData

@Model
final class Environment {
    var id: UUID
    var name: String
    var workspace: Workspace?
    @Relationship(deleteRule: .cascade, inverse: \EnvironmentVariable.environment) var variables: [EnvironmentVariable]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.variables = []
    }
}
