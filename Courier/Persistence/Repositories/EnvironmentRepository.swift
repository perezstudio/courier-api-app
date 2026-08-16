import CoreData
import Foundation

/// Environments and variables.
///
/// Secret values never pass through here — the repository writes an empty
/// `value` and the caller stores the real one in `SecretStore` under the
/// variable's id. See REQUIREMENTS.md §6.
@MainActor
final class EnvironmentRepository {

    private let context: NSManagedObjectContext
    private let secretStore: SecretStore

    init(context: NSManagedObjectContext, secretStore: SecretStore) {
        self.context = context
        self.secretStore = secretStore
    }

    // MARK: - Environments

    func environments(forWorkspace workspaceID: UUID) throws -> [EnvironmentSnapshot] {
        let request = CDEnvironment.fetchRequest()
        request.predicate = NSPredicate(format: "workspace.id == %@", workspaceID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request).map(Self.snapshot(of:))
    }

    @discardableResult
    func createEnvironment(name: String, inWorkspace workspaceID: UUID) throws -> EnvironmentSnapshot {
        let workspaceRequest = CDWorkspace.fetchRequest()
        workspaceRequest.predicate = NSPredicate(format: "id == %@", workspaceID as CVarArg)
        workspaceRequest.fetchLimit = 1
        guard let workspace = try context.fetch(workspaceRequest).first else {
            throw LibraryRepository.RepositoryError.notFound
        }

        // Counted before attaching: setting the relationship first would make
        // the new environment one of its own siblings.
        let sortOrder = workspace.environments.count

        let environment = CDEnvironment(context: context)
        environment.name = name
        environment.workspace = workspace
        environment.sortOrder = Int32(sortOrder)
        try context.save()
        return Self.snapshot(of: environment)
    }

    func renameEnvironment(id: UUID, to name: String) throws {
        let environment = try fetchEnvironment(id)
        environment.name = name
        try context.save()
    }

    func deleteEnvironment(id: UUID) throws {
        let environment = try fetchEnvironment(id)
        // Cascade removes the variables, so their Keychain items must go first
        // or they would be orphaned with no record pointing at them.
        for variable in environment.variables where variable.isSecret {
            try? secretStore.delete(for: variable.id)
        }
        context.delete(environment)
        try context.save()
    }

    // MARK: - Variables

    @discardableResult
    func addVariable(
        key: String,
        value: String,
        isSecret: Bool,
        toEnvironment environmentID: UUID
    ) throws -> VariableSnapshot {
        let environment = try fetchEnvironment(environmentID)
        let sortOrder = environment.variables.count

        let variable = CDVariable(context: context)
        variable.key = key
        variable.isSecret = isSecret
        variable.environment = environment
        variable.sortOrder = Int32(sortOrder)
        variable.value = isSecret ? "" : value

        if isSecret {
            try secretStore.set(value, for: variable.id)
        }

        try context.save()
        return Self.snapshot(of: variable)
    }

    /// Updates a variable, moving its value between Core Data and the Keychain
    /// when its secret flag changes.
    func updateVariable(
        id: UUID,
        key: String,
        value: String,
        isSecret: Bool,
        isEnabled: Bool
    ) throws {
        let variable = try fetchVariable(id)
        let wasSecret = variable.isSecret

        variable.key = key
        variable.isEnabled = isEnabled
        variable.isSecret = isSecret

        if isSecret {
            variable.value = ""
            try secretStore.set(value, for: id)
        } else {
            variable.value = value
            if wasSecret {
                try? secretStore.delete(for: id)
            }
        }

        try context.save()
    }

    func deleteVariable(id: UUID) throws {
        let variable = try fetchVariable(id)
        if variable.isSecret {
            try? secretStore.delete(for: id)
        }
        context.delete(variable)
        try context.save()
    }

    /// Resolves a variable's value, reading secrets from the Keychain.
    func value(for variableID: UUID) throws -> String? {
        let variable = try fetchVariable(variableID)
        return variable.isSecret ? try secretStore.value(for: variableID) : variable.value
    }

    // MARK: - Orphan sweep

    /// Deletes Keychain items whose variable no longer exists.
    ///
    /// Runs at launch. A delete that fails partway, or a store restored from a
    /// backup taken before a variable was added, can both leave items behind —
    /// and an orphaned secret is invisible to the user, so nothing else would
    /// ever clean it up. See REQUIREMENTS.md §6.
    @discardableResult
    func sweepOrphanedSecrets() throws -> Int {
        let request = CDVariable.fetchRequest()
        request.predicate = NSPredicate(format: "isSecret == YES")
        let live = Set(try context.fetch(request).map(\.id))

        let stored = try secretStore.allIdentifiers()
        let orphans = stored.subtracting(live)
        for orphan in orphans {
            try? secretStore.delete(for: orphan)
        }
        return orphans.count
    }

    // MARK: - Helpers

    private func fetchEnvironment(_ id: UUID) throws -> CDEnvironment {
        let request = CDEnvironment.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let result = try context.fetch(request).first else {
            throw LibraryRepository.RepositoryError.notFound
        }
        return result
    }

    private func fetchVariable(_ id: UUID) throws -> CDVariable {
        let request = CDVariable.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let result = try context.fetch(request).first else {
            throw LibraryRepository.RepositoryError.notFound
        }
        return result
    }

    static func snapshot(of environment: CDEnvironment) -> EnvironmentSnapshot {
        EnvironmentSnapshot(
            id: environment.id,
            name: environment.name,
            sortOrder: Int(environment.sortOrder),
            variables: environment.variables
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(snapshot(of:))
        )
    }

    static func snapshot(of variable: CDVariable) -> VariableSnapshot {
        VariableSnapshot(
            id: variable.id,
            key: variable.key,
            value: variable.value,
            isSecret: variable.isSecret,
            isEnabled: variable.isEnabled,
            sortOrder: Int(variable.sortOrder)
        )
    }
}
